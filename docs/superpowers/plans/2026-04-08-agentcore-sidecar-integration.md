# AgentCore Sidecar Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** route.ts의 Bedrock 직접 호출/도구 코드를 제거하고, agent.py를 SSE 스트리밍 사이드카로 전환하여 단일 진입점으로 통합한다.

**Architecture:** Next.js route.ts(~50줄 SSE 프록시) → agent.py(port 8080, stream_async 기반 SSE 스트리밍) → Strands Agent(Bedrock Converse API + native tool_use + Memory + Gateway).

**Tech Stack:** Python 3.12 (Strands SDK, bedrock-agentcore), TypeScript (Next.js 14), systemd

**Spec:** `docs/superpowers/specs/2026-04-08-agentcore-sidecar-integration-design.md`

---

### Task 1: agent.py — StreamingHook 추가

**Files:**
- Modify: `agentcore/agent.py:16` (imports)
- Modify: `agentcore/agent.py:122` (MemoryHook 뒤에 StreamingHook 추가)

- [ ] **Step 1: imports에 BeforeToolCallEvent, AfterToolCallEvent 추가**

`agentcore/agent.py` 16줄의 import를 변경:

```python
# 변경 전
from strands.hooks import AgentInitializedEvent, HookProvider, MessageAddedEvent

# 변경 후
import queue
from strands.hooks import (
    AgentInitializedEvent, BeforeToolCallEvent, AfterToolCallEvent,
    HookProvider, MessageAddedEvent,
)
```

- [ ] **Step 2: StreamingHook 클래스 추가**

`agentcore/agent.py`의 MemoryHook 클래스(`register_hooks` 메서드) 바로 뒤, `create_gateway_transport` 함수 앞에 삽입:

```python
# ─── Streaming Hook ──────────────────────────────────────────────────────────
class StreamingHook(HookProvider):
    """도구 실행 상태를 queue에 전달하여 SSE 스트리밍에 사용."""

    TOOL_LABELS = {
        "query_athena": "Athena", "search_logs": "CW Logs",
        "get_metrics": "Metrics", "describe_alarms": "Alarms",
        "select_s3_object": "S3 Select", "get_table_schema": "Glue",
        "create_grafana_annotation": "Grafana", "publish_sns": "SNS",
    }

    def __init__(self):
        self.events: queue.Queue = queue.Queue()

    def _label(self, event) -> str:
        name = event.tool_use.get("name", "") if hasattr(event, "tool_use") else ""
        return self.TOOL_LABELS.get(name, name)

    def _on_before_tool(self, event: BeforeToolCallEvent) -> None:
        label = self._label(event)
        if label:
            self.events.put({"type": "status", "content": f"{label} 분석 중..."})

    def _on_after_tool(self, event: AfterToolCallEvent) -> None:
        label = self._label(event)
        if label:
            prefix = "\u26a0\ufe0f" if getattr(event, "exception", None) else "\u2705"
            self.events.put({"type": "status", "content": f"{prefix} {label} 완료"})

    def register_hooks(self, registry):
        registry.add_callback(BeforeToolCallEvent, self._on_before_tool)
        registry.add_callback(AfterToolCallEvent, self._on_after_tool)
```

- [ ] **Step 3: agent.py를 직접 실행하여 import 오류 없는지 확인**

Run: `cd agentcore && python3 -c "import agent; print('OK')"` (또는 Docker 환경에서)
Expected: `OK` (import 성공)

- [ ] **Step 4: Commit**

```bash
git add agentcore/agent.py
git commit -m "feat(agentcore): add StreamingHook for tool execution status events"
```

---

### Task 2: agent.py — entrypoint를 streaming generator로 변환

**Files:**
- Modify: `agentcore/agent.py:379` (`create_agent` 함수)
- Modify: `agentcore/agent.py:418-436` (entrypoint + main)

- [ ] **Step 1: create_agent에 streaming_hook 파라미터 추가**

`agentcore/agent.py`의 `create_agent` 함수를 변경:

```python
# 변경 전
def create_agent(session_id: str = "default") -> Agent:
    """Create Strands agent with MCP Gateway tools + direct tools."""
    tools = list(DIRECT_TOOLS)
    model_id = "global.anthropic.claude-sonnet-4-6"

    # ... (MCP Gateway 연결 코드 유지) ...

    hooks = [MemoryHook()] if MEMORY_ID else []

    return Agent(
        model=model_id,
        system_prompt=SYSTEM_PROMPT,
        tools=tools,
        hooks=hooks,
        state={"session_id": session_id},
    )

# 변경 후
def create_agent(session_id: str = "default", streaming_hook: StreamingHook | None = None) -> Agent:
    """Create Strands agent with MCP Gateway tools + direct tools."""
    tools = list(DIRECT_TOOLS)
    model_id = "global.anthropic.claude-sonnet-4-6"

    # ... (MCP Gateway 연결 코드 유지 — 변경 없음) ...

    hooks: list = [MemoryHook()] if MEMORY_ID else []
    if streaming_hook:
        hooks.append(streaming_hook)

    return Agent(
        model=model_id,
        system_prompt=SYSTEM_PROMPT,
        tools=tools,
        hooks=hooks,
        callback_handler=None,  # 스트리밍 시 기본 콜백 비활성화
        state={"session_id": session_id},
    )
```

- [ ] **Step 2: split_chunks 유틸 함수 추가**

entrypoint 함수 바로 위에 추가:

```python
def split_chunks(text: str, size: int = 30) -> list[str]:
    """텍스트를 지정 크기로 분할."""
    return [text[i:i + size] for i in range(0, len(text), size)]
```

- [ ] **Step 3: 파일 상단 imports에 asyncio, concurrent.futures, time 추가**

`agentcore/agent.py` 파일 상단 imports 영역 (`import queue` 뒤)에 추가:

```python
import asyncio
import concurrent.futures
import time
```

그리고 `# ─── Config ───` 섹션 바로 앞에 executor 추가:

```python
_executor = concurrent.futures.ThreadPoolExecutor(max_workers=4)
```

- [ ] **Step 4: entrypoint를 async streaming generator로 변환**

`agentcore/agent.py`의 entrypoint 전체를 교체:

```python
# 변경 전
@app.entrypoint
def invoke(payload, context):
    session_id = getattr(context, "session_id", "default")
    user_message = payload.get("prompt", "오늘 RUM 현황을 알려주세요")

    logger.info(f"[{session_id}] User: {user_message[:100]}")

    agent = create_agent(session_id)
    response = agent(user_message)

    result_text = response.message["content"][0]["text"]
    logger.info(f"[{session_id}] Response: {result_text[:100]}...")

    return {"result": result_text}


if __name__ == "__main__":
    app.run()

# 변경 후


@app.entrypoint
async def invoke(payload, context):
    session_id = payload.get("session_id", getattr(context, "session_id", "default"))
    user_message = payload.get("prompt", "오늘 RUM 현황을 알려주세요")

    logger.info(f"[{session_id}] User: {user_message[:100]}")

    yield {"type": "start"}
    yield {"type": "status", "content": "\U0001f50d 분석 중... 리포트를 생성중입니다."}

    streaming_hook = StreamingHook()
    agent = create_agent(session_id, streaming_hook=streaming_hook)

    # Strands agent는 동기 함수이므로 별도 스레드에서 실행
    loop = asyncio.get_event_loop()
    future = loop.run_in_executor(_executor, agent, user_message)

    last_heartbeat = time.time()

    while not future.done():
        # hook queue에서 도구 상태 이벤트를 yield
        try:
            event = streaming_hook.events.get_nowait()
            yield event
        except queue.Empty:
            pass

        # 15초 간격 heartbeat
        now = time.time()
        if now - last_heartbeat > 15:
            yield {"type": "heartbeat"}
            last_heartbeat = now

        await asyncio.sleep(0.3)

    # queue에 남은 이벤트 flush
    while not streaming_hook.events.empty():
        yield streaming_hook.events.get_nowait()

    # 결과 처리
    try:
        response = future.result()
        result_text = response.message["content"][0]["text"]
        logger.info(f"[{session_id}] Response: {result_text[:100]}...")

        for chunk in split_chunks(result_text, 30):
            yield {"type": "chunk", "content": chunk}
    except Exception as e:
        logger.error(f"[{session_id}] Error: {e}")
        yield {"type": "error", "content": str(e)}

    yield {"type": "done"}


if __name__ == "__main__":
    app.run()
```

- [ ] **Step 5: agent.py 로컬 실행 테스트**

Run:
```bash
cd agentcore && python3 agent.py &
sleep 3
curl -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"prompt": "ping", "session_id": "test"}' \
  --no-buffer
```
Expected: SSE 형식의 이벤트 스트림 (`data: {"type": "start"}`, `data: {"type": "done"}`)

- [ ] **Step 6: health check 확인**

Run: `curl http://localhost:8080/ping`
Expected: `{"status": "Healthy", ...}`

- [ ] **Step 7: Commit**

```bash
git add agentcore/agent.py
git commit -m "feat(agentcore): convert entrypoint to async streaming generator"
```

---

### Task 3: route.ts — SSE 프록시로 교체

**Files:**
- Modify: `agentcore/web-app/app/api/chat/route.ts` (전체 교체)

- [ ] **Step 1: route.ts 전체를 SSE 프록시로 교체**

`agentcore/web-app/app/api/chat/route.ts` 전체를 다음으로 교체 (기존 313줄 → 약 45줄):

```typescript
import { NextRequest } from 'next/server';

const AGENT_URL = process.env.AGENT_URL || 'http://localhost:8080/invocations';
const AGENT_TIMEOUT = Number(process.env.AGENT_TIMEOUT || '180000'); // 180초

export async function POST(request: NextRequest) {
  const userSub = request.headers.get('x-user-sub') || 'anonymous';

  let body: { prompt?: string };
  try {
    body = await request.json();
  } catch {
    return new Response(JSON.stringify({ error: 'invalid JSON' }), { status: 400 });
  }

  const { prompt } = body;
  if (!prompt) {
    return new Response(JSON.stringify({ error: 'prompt required' }), { status: 400 });
  }

  let agentResp: Response;
  try {
    agentResp = await fetch(AGENT_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ prompt, session_id: userSub }),
      signal: AbortSignal.timeout(AGENT_TIMEOUT),
    });
  } catch (e) {
    const msg = e instanceof Error ? e.message : 'Agent unavailable';
    return new Response(JSON.stringify({ error: msg }), { status: 502 });
  }

  if (!agentResp.ok || !agentResp.body) {
    const text = await agentResp.text().catch(() => 'unknown error');
    return new Response(JSON.stringify({ error: text }), { status: agentResp.status || 502 });
  }

  return new Response(agentResp.body, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      Connection: 'keep-alive',
    },
  });
}
```

- [ ] **Step 2: Commit**

```bash
git add agentcore/web-app/app/api/chat/route.ts
git commit -m "refactor(agent-ui): replace Bedrock direct call with agent.py SSE proxy"
```

---

### Task 4: 불필요한 npm 의존성 제거

**Files:**
- Modify: `agentcore/web-app/package.json`

- [ ] **Step 1: AWS SDK 의존성 6개 제거**

`agentcore/web-app/package.json`의 dependencies에서 다음 6개 패키지를 삭제:

```json
// 삭제할 패키지들
"@aws-sdk/client-lambda": "^3.700.0",
"@aws-sdk/client-bedrock-runtime": "^3.700.0",
"@aws-sdk/client-cloudwatch-logs": "^3.700.0",
"@aws-sdk/client-cloudwatch": "^3.700.0",
"@aws-sdk/client-glue": "^3.700.0",
"@aws-sdk/client-sns": "^3.700.0",
```

변경 후 `package.json` dependencies:

```json
"dependencies": {
  "next": "^14.2.0",
  "react": "^18.3.0",
  "react-dom": "^18.3.0",
  "react-markdown": "^10.0.0",
  "remark-gfm": "^4.0.0"
}
```

- [ ] **Step 2: node_modules 재설치 및 빌드 확인**

Run:
```bash
cd agentcore/web-app && rm -rf node_modules package-lock.json && npm install && npm run build
```
Expected: 빌드 성공 (route.ts가 더 이상 AWS SDK를 import하지 않으므로)

- [ ] **Step 3: Commit**

```bash
git add agentcore/web-app/package.json agentcore/web-app/package-lock.json
git commit -m "chore(agent-ui): remove unused AWS SDK dependencies"
```

---

### Task 5: systemd 서비스 파일 생성

**Files:**
- Create: `agentcore/rum-agent.service`

- [ ] **Step 1: systemd 유닛 파일 생성**

`agentcore/rum-agent.service` 파일을 생성:

```ini
[Unit]
Description=RUM AgentCore Agent (Strands + Bedrock Sonnet 4.6)
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/rum-agent-ui/agentcore
EnvironmentFile=/opt/rum-agent-ui/.env
ExecStart=/usr/bin/python3 agent.py
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal
SyslogIdentifier=rum-agent

[Install]
WantedBy=multi-user.target
```

- [ ] **Step 2: Commit**

```bash
git add agentcore/rum-agent.service
git commit -m "feat(agentcore): add systemd service for agent.py sidecar"
```

---

### Task 6: Terraform user_data 업데이트

**Files:**
- Modify: `terraform/modules/agent-ui/main.tf:158-176` (user_data 블록)

- [ ] **Step 1: user_data에 agent.py 서비스 등록 추가**

`terraform/modules/agent-ui/main.tf`의 user_data 블록을 변경. 기존 `ENV` heredoc 종료 후, `echo "EC2 초기화 완료..."` 줄 앞에 agent.py 설정을 삽입:

```bash
# 변경 전 (기존 user_data 끝부분)
    echo "EC2 초기화 완료. Next.js 앱을 배포해 주세요."

# 변경 후
    # agent.py 사이드카 서비스 설정
    pip3 install -r /opt/rum-agent-ui/agentcore/requirements.txt

    cp /opt/rum-agent-ui/agentcore/rum-agent.service /etc/systemd/system/
    systemctl daemon-reload
    systemctl enable --now rum-agent

    echo "EC2 초기화 완료. Next.js 앱을 배포해 주세요."
```

- [ ] **Step 2: terraform fmt 실행**

Run: `cd terraform && terraform fmt -recursive`
Expected: 포맷팅 변경 사항 없거나 자동 수정

- [ ] **Step 3: Commit**

```bash
git add terraform/modules/agent-ui/main.tf
git commit -m "feat(agent-ui): add agent.py sidecar setup to EC2 user_data"
```

---

### Task 7: 통합 테스트

**Files:**
- No new files (수동 테스트)

- [ ] **Step 1: agent.py 로컬 실행**

Run:
```bash
cd agentcore
export AWS_REGION=ap-northeast-2
python3 agent.py &
AGENT_PID=$!
sleep 3
```

- [ ] **Step 2: agent.py 직접 호출 테스트**

Run:
```bash
curl -s -X POST http://localhost:8080/invocations \
  -H "Content-Type: application/json" \
  -d '{"prompt": "RUM 테이블 스키마를 확인해줘", "session_id": "test-user"}' \
  --no-buffer
```
Expected: SSE 형식 이벤트 스트림:
```
data: {"type": "start"}
data: {"type": "status", "content": "\ud83d\udd0d 분석 중... 리포트를 생성중입니다."}
data: {"type": "status", "content": "Glue 분석 중..."}
data: {"type": "status", "content": "\u2705 Glue 완료"}
data: {"type": "chunk", "content": "## rum_events 테이블 스키"}
data: {"type": "chunk", "content": "마\n\n| 컬럼 | 타입 |..."}
data: {"type": "done"}
```

- [ ] **Step 3: Next.js → agent.py 프록시 테스트**

Run:
```bash
cd agentcore/web-app && npm run dev &
sleep 5
curl -s -X POST http://localhost:3000/api/chat \
  -H "Content-Type: application/json" \
  -H "x-user-sub: test-user" \
  -d '{"prompt": "오늘 에러 현황은?"}' \
  --no-buffer
```
Expected: 동일한 SSE 이벤트 스트림이 프록시를 통해 전달

- [ ] **Step 4: 프로세스 정리**

Run:
```bash
kill $AGENT_PID
# Next.js 프로세스도 정리
```

- [ ] **Step 5: Commit (테스트 통과 후 최종)**

```bash
git add -A
git commit -m "test: verify agent.py sidecar + route.ts proxy integration"
```

---

### Task 8: 문서 업데이트

**Files:**
- Modify: `docs/architecture.md` (AI Analysis Agent 섹션)
- Modify: `agentcore/CLAUDE.md`

- [ ] **Step 1: architecture.md 한국어 섹션 — Analysis Agent 업데이트**

`docs/architecture.md`의 한국어 Analysis Agent 섹션을 변경:

```markdown
### Analysis Agent
- **agentcore/** — Bedrock AgentCore 기반 RUM 분석 에이전트.
  - `agent.py` — Strands Agent (Claude Sonnet 4.6) + 8개 도구. SSE 스트리밍 사이드카 (port 8080).
  - Athena/Trino 금지 함수 규칙. 라운드당 최대 2개 도구 호출 제한. StreamingHook으로 도구 실행 상태 전달.
  - `web-app/` — Next.js 14 Web UI. route.ts는 agent.py의 SSE 프록시 역할 (~50줄).
- **terraform/modules/agent-ui/** — AgentCore UI 호스팅 인프라 + agent.py systemd 서비스.
```

- [ ] **Step 2: architecture.md 영문 섹션 — Analysis Agent 업데이트**

```markdown
### Analysis Agent
- **agentcore/** — Bedrock AgentCore-based RUM analysis agent.
  - `agent.py` — Strands Agent (Claude Sonnet 4.6) + 8 tools. SSE streaming sidecar (port 8080).
  - Athena/Trino forbidden function rules. Max 2 tool calls per round. StreamingHook for tool execution status.
  - `web-app/` — Next.js 14 Web UI. route.ts acts as SSE proxy to agent.py (~50 lines).
- **terraform/modules/agent-ui/** — AgentCore UI hosting infrastructure + agent.py systemd service.
```

- [ ] **Step 3: architecture.md Key Design Decisions에 추가 (한국어)**

```markdown
- agent.py를 SSE 스트리밍 사이드카로 실행, route.ts는 프록시로 역할 분리 (코드 중복 제거, 단일 프롬프트/도구 관리)
```

- [ ] **Step 4: architecture.md Key Design Decisions에 추가 (영문)**

```markdown
- agent.py runs as SSE streaming sidecar, route.ts acts as proxy (eliminates code duplication, single prompt/tool management)
```

- [ ] **Step 5: agentcore/CLAUDE.md 업데이트**

Key Files 섹션에 추가:
```markdown
- `rum-agent.service` — agent.py systemd 서비스 유닛 파일
```

Rules 섹션에 추가:
```markdown
- route.ts는 agent.py의 SSE 프록시 역할만 수행 (Bedrock 직접 호출 금지)
- 도구 추가/프롬프트 변경은 agent.py에서만 수행 (route.ts 변경 불필요)
```

- [ ] **Step 6: Commit**

```bash
git add docs/architecture.md agentcore/CLAUDE.md
git commit -m "docs: update architecture and CLAUDE.md for sidecar integration"
```
