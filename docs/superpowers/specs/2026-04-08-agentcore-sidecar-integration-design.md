# route.ts → agent.py 사이드카 통합 설계

## 배경

현재 Agent UI의 Next.js `route.ts`와 `agent.py`가 각각 독립적으로 Bedrock Sonnet 4.6을 호출하며 코드 중복(시스템 프롬프트, 도구 구현, SQL 규칙)이 발생. route.ts의 XML 태그 파싱은 취약하고, AgentCore Memory/Gateway를 활용하지 못함.

## 목표

- route.ts를 SSE 프록시(~50줄)로 축소, agent.py를 단일 진입점으로 통합
- 코드 중복 제거 (~260줄 삭제)
- AgentCore Memory (per-user 대화 히스토리) 활성화
- MCP Gateway (Athena) 활용
- 프론트엔드 변경 없음 (SSE 이벤트 포맷 동일 유지)

## 아키텍처

```
Browser (Chat UI)
    │ POST /api/chat { prompt }
    ▼
Next.js route.ts (SSE 프록시, ~50줄)
    │ POST http://localhost:8080/invocations
    │   { "prompt": "...", "session_id": "user-sub-xxx" }
    ▼
agent.py (Starlette/uvicorn, port 8080)
    │ @app.entrypoint (streaming generator)
    │ yield SSE events → route.ts → Browser
    ▼
Strands Agent (Claude Sonnet 4.6)
    ├── Bedrock Converse API (native tool_use)
    ├── MCP Gateway (Athena Query Lambda)
    ├── Direct Tools (CW Logs/Metrics/Alarms, S3 Select, Glue, Grafana, SNS)
    └── AgentCore Memory (per-user, via MEMORY_ID)
```

## 변경 사항

### 1. agent.py — streaming generator 변환

현재 `invoke()`는 최종 결과만 반환:

```python
@app.entrypoint
def invoke(payload, context):
    agent = create_agent(session_id)
    response = agent(user_message)
    return {"result": result_text}
```

변경 후, generator로 SSE 이벤트를 yield:

```python
@app.entrypoint
def invoke(payload, context):
    hook = StreamingHook()
    agent = create_agent(session_id, hooks=[hook])

    yield {"type": "status", "content": "분석 중... 리포트를 생성중입니다."}

    future = executor.submit(agent, user_message)

    while not future.done():
        try:
            event = hook.events.get(timeout=0.5)
            yield event
        except queue.Empty:
            # 15초 heartbeat
            if time.time() - last_heartbeat > 15:
                yield {"type": "heartbeat"}
                last_heartbeat = time.time()

    response = future.result()
    result_text = response.message["content"][0]["text"]
    for chunk in split_chunks(result_text, 30):
        yield {"type": "chunk", "content": chunk}
    yield {"type": "done"}
```

#### StreamingHook

Strands HookProvider를 활용하여 도구 실행 상태를 캡처. 구현 시 Strands Hook API의 정확한 이벤트명(`ToolUseEvent`, `ToolResultEvent` 등)을 확인 필요 — 아래는 의도를 보여주는 의사 코드:

```python
class StreamingHook(HookProvider):
    TOOL_LABELS = {
        "query_athena": "Athena", "search_logs": "CW Logs",
        "get_metrics": "Metrics", "describe_alarms": "Alarms",
        "select_s3_object": "S3 Select", "get_table_schema": "Glue",
        "create_grafana_annotation": "Grafana", "publish_sns": "SNS",
    }

    def __init__(self):
        self.events = queue.Queue()

    def on_tool_start(self, event):  # 실제 Strands 이벤트명 확인 필요
        label = self.TOOL_LABELS.get(event.tool_name, event.tool_name)
        self.events.put({"type": "status", "content": f"{label} 분석 중..."})

    def on_tool_end(self, event):    # 실제 Strands 이벤트명 확인 필요
        label = self.TOOL_LABELS.get(event.tool_name, event.tool_name)
        self.events.put({"type": "status", "content": f"✅ {label} 완료"})
```

#### split_chunks 유틸리티

텍스트를 지정 크기로 분할하는 간단한 유틸:

```python
def split_chunks(text: str, size: int = 30) -> list[str]:
    return [text[i:i+size] for i in range(0, len(text), size)]
```

`BedrockAgentCoreApp`은 generator를 감지하면 자동으로 `StreamingResponse(media_type="text/event-stream")`로 래핑.

### 2. route.ts — SSE 프록시 (~50줄)

~300줄 → ~50줄. Bedrock 직접 호출, 도구 함수, 태그 파싱 코드 전부 제거.

```typescript
import { NextRequest } from 'next/server';

const AGENT_URL = process.env.AGENT_URL || 'http://localhost:8080/invocations';

export async function POST(request: NextRequest) {
  const userSub = request.headers.get('x-user-sub') || 'anonymous';
  const { prompt } = await request.json();
  if (!prompt) return new Response(JSON.stringify({ error: 'prompt required' }), { status: 400 });

  const agentResp = await fetch(AGENT_URL, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ prompt, session_id: userSub }),
    signal: AbortSignal.timeout(180_000),
  });

  if (!agentResp.ok || !agentResp.body) {
    return new Response(JSON.stringify({ error: 'Agent unavailable' }), { status: 502 });
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

#### 삭제 대상

| 삭제 항목 | 줄 수 |
|-----------|-------|
| AWS SDK 클라이언트 7개 (Lambda, CW Logs, CW, Glue, SNS, BedrockRuntime) | ~20줄 |
| 시스템 프롬프트 (SYSTEM_PROMPT) | ~80줄 |
| 도구 함수 7개 (queryAthena, searchLogs, getMetrics 등) | ~80줄 |
| 태그 파싱 (extractToolTags, runTool, stripTags) | ~30줄 |
| callBedrock() + 멀티라운드 오케스트레이션 | ~50줄 |
| **합계** | **~260줄** |

#### 환경변수 변경

삭제 (route.ts에서): `BEDROCK_MODEL`, `ATHENA_LAMBDA`, `SNS_TOPIC_ARN`, `GRAFANA_URL`, `GRAFANA_API_KEY`

추가 (선택적): `AGENT_URL=http://localhost:8080/invocations`

유지 (agent.py .env로): `AWS_REGION`, `PROJECT_NAME`, `SNS_TOPIC_ARN`, `GRAFANA_URL`, `GRAFANA_API_KEY`, `MEMORY_ID`, `GATEWAY_URL`, `S3_RAW_BUCKET`

### 3. systemd 서비스 — rum-agent.service

```ini
[Unit]
Description=RUM AgentCore Agent
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/opt/rum-agent-ui/agentcore
EnvironmentFile=/opt/rum-agent-ui/.env
ExecStart=/usr/bin/python3 agent.py
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 4. Terraform user_data 변경

`terraform/modules/agent-ui/main.tf` user_data에 추가:

```bash
pip3 install -r /opt/rum-agent-ui/agentcore/requirements.txt
cp /opt/rum-agent-ui/rum-agent.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now rum-agent
```

## SSE 이벤트 포맷 (route.ts ↔ 브라우저 계약)

```json
{"type": "status", "content": "📊 Athena 분석 중..."}
{"type": "status", "content": "✅ Athena 3건 완료"}
{"type": "chunk",  "content": "## 오늘 RUM 현황\n\n"}
{"type": "done"}
{"type": "error",  "content": "Athena timeout"}
{"type": "heartbeat"}
```

현재 route.ts가 브라우저에 보내는 포맷과 동일. 프론트엔드 변경 없음.

## EC2 프로세스 구조

```
EC2 (t4g.large, 2 vCPU, 8GB RAM)
├── rum-agent.service (systemd)
│   └── python3 agent.py          ← port 8080
│       ├── POST /invocations     ← SSE streaming
│       └── GET /ping             ← health check
│
└── Next.js 14 (PM2 or systemd)
    └── node server.js            ← port 3000
        └── POST /api/chat        ← SSE 프록시 → localhost:8080
```

## 에러 처리

| 상황 | 처리 |
|------|------|
| agent.py 미기동 | fetch() ECONNREFUSED → 502 응답 |
| agent.py 내부 에러 | SSE `{"type":"error"}` 이벤트로 전달 |
| agent.py 타임아웃 | AbortSignal.timeout(180_000) → 504 |

## 헬스체크

- ALB: 기존 Next.js `/` 경로 유지
- agent.py: `GET /ping` → `{"status": "Healthy"}`
- 선택적: Next.js `/api/health`에서 agent.py ping 확인

## 변경하지 않는 것

- 프론트엔드 (`page.tsx`) — SSE 이벤트 포맷 동일
- agent.py의 기존 도구/프롬프트/Memory 로직 (구조만 generator로 변경)
- Terraform IAM 정책 (이미 `bedrock-agentcore:*` 포함)
- CDK 구성
- web-app의 나머지 파일 (layout.tsx, page.tsx 등)

## 배포 순서

1. agent.py 스트리밍 변경 + StreamingHook 추가
2. rum-agent.service 생성
3. route.ts SSE 프록시로 교체
4. 불필요한 npm 의존성 제거
5. Terraform user_data 업데이트
6. 테스트 (로컬 → EC2)

## 향후 확장

- AgentCore Runtime(관리형)으로 전환 시: `AGENT_URL`만 관리형 엔드포인트로 변경. agent.py와 route.ts 코드 변경 없음.
- 도구 추가: agent.py에만 추가하면 됨 (route.ts 변경 불필요)
- 프롬프트 튜닝: agent.py의 SYSTEM_PROMPT만 수정
