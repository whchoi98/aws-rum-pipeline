<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## AgentCore Module

### Role
Bedrock AgentCore 기반 RUM 분석 에이전트 (Claude Sonnet 4.6).
8개 도구로 RUM 데이터, 인프라 로그/메트릭, 알람을 종합 분석.
Next.js 14 Web UI를 통해 채팅 인터페이스 + 리포트 다운로드 제공.

### 분석 도구 (8개)
| 도구 | 태그 | 역할 |
|------|------|------|
| Athena SQL | `<SQL>` | RUM 이벤트 쿼리 (기본) |
| CloudWatch Logs | `<CWLOGS>` | Lambda 에러 로그 검색 |
| CloudWatch Metrics | `<METRICS>` | 인프라 성능 메트릭 |
| CloudWatch Alarms | `<ALARM>` | 알람 상태 점검 |
| S3 Select | (agent.py) | raw 이벤트 직접 조회 |
| Glue Catalog | `<GLUE>` | 테이블 스키마 확인 |
| Grafana API | `<GRAFANA>` | 대시보드 어노테이션 |
| SNS Publish | `<SNS>` | 분석 리포트 발송 |

### Key Files
- `agent.py` — 에이전트 메인. Strands Agent + 8개 boto3 도구 + MCP Gateway
- `requirements.txt` — Python 의존성 (strands-agents, boto3 등)
- `streamable_http_sigv4.py` — SigV4 인증 HTTP 클라이언트 유틸리티
- `web-app/` — Next.js 14 Web UI (에이전트 채팅 인터페이스, 메인 앱)
- `Dockerfile` — 에이전트 컨테이너 이미지
- `proxy.py` — EC2에서 실행되는 HTTP 프록시. boto3 invoke-agent-runtime으로 AgentCore Runtime 호출, SSE 스트리밍 중계 (port 8080)
- `requirements-proxy.txt` — EC2 proxy.py 의존성 (starlette, uvicorn, websockets, boto3)
- `rum-agent.service` — proxy.py systemd 서비스 유닛 파일
- `scripts/setup-agentcore.sh` — AgentCore 환경 설정 스크립트 (프로젝트 루트 `scripts/` 에 위치)

### Key Commands
```bash
# 에이전트 실행
pip install -r requirements.txt
python3 agent.py

# Web UI 개발
cd web-app && npm install && npm run dev

# 컨테이너 빌드
docker build -t rum-agentcore .

# EC2 프록시 실행
pip3 install -r requirements-proxy.txt
python3 proxy.py   # localhost:8080
```

### Rules
- AWS 자격증명은 IAM Role 또는 환경변수로 주입
- Bedrock 모델 ID는 환경변수로 설정
- MCP 도구는 `agent.py` 내 도구 목록으로 관리
- Athena 쿼리는 파티션 필터 필수 (비용 최적화)
- route.ts → proxy.py(localhost:8080) → AgentCore Runtime 경로로만 에이전트 호출
- route.ts는 agent.py의 SSE 프록시 역할만 수행 (Bedrock 직접 호출 금지)
- 도구 추가/프롬프트 변경은 agent.py에서만 수행 (route.ts 변경 불필요)

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## AgentCore Module

### Role
A RUM analytics agent powered by Bedrock AgentCore (Claude Sonnet 4.6).
8 tools for comprehensive analysis: RUM data, infra logs/metrics, alarms.
Provides a chat interface with report download via Next.js 14 Web UI.

### Analysis Tools (8)
| Tool | Tag | Purpose |
|------|-----|---------|
| Athena SQL | `<SQL>` | RUM event queries (primary) |
| CloudWatch Logs | `<CWLOGS>` | Lambda error log search |
| CloudWatch Metrics | `<METRICS>` | Infrastructure performance |
| CloudWatch Alarms | `<ALARM>` | Alarm status check |
| S3 Select | (agent.py) | Direct raw event queries |
| Glue Catalog | `<GLUE>` | Table schema lookup |
| Grafana API | `<GRAFANA>` | Dashboard annotations |
| SNS Publish | `<SNS>` | Report distribution |

### Key Files
- `agent.py` — Agent main entry. Strands Agent + 8 boto3 tools + MCP Gateway
- `requirements.txt` — Python dependencies (strands-agents, boto3, etc.)
- `streamable_http_sigv4.py` — SigV4 authenticated HTTP client utility
- `web-app/` — Next.js 14 Web UI (agent chat interface, main app)
- `Dockerfile` — Agent container image
- `proxy.py` — HTTP proxy running on EC2. Calls AgentCore Runtime via boto3 invoke-agent-runtime, relays SSE stream (port 8080)
- `requirements-proxy.txt` — EC2 proxy.py dependencies (starlette, uvicorn, websockets, boto3)
- `rum-agent.service` — proxy.py systemd service unit file
- `scripts/setup-agentcore.sh` — AgentCore environment setup script (located in project root `scripts/`)

### Key Commands
```bash
# Run agent
pip install -r requirements.txt
python3 agent.py

# Web UI development
cd web-app && npm install && npm run dev

# Container build
docker build -t rum-agentcore .

# EC2 proxy
pip3 install -r requirements-proxy.txt
python3 proxy.py   # localhost:8080
```

### Rules
- AWS credentials injected via IAM Role or environment variables
- Bedrock model ID set via environment variable
- MCP tools managed as a tool list within `agent.py`
- Athena queries must include partition filters (cost optimization)
- route.ts → proxy.py(localhost:8080) → AgentCore Runtime is the only agent call path
- route.ts only acts as SSE proxy for agent.py (no direct Bedrock calls)
- Tool additions/prompt changes only need to be made in agent.py (route.ts changes not required)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
