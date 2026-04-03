# AgentCore Module

## Role
Bedrock AgentCore 기반 RUM 분석 에이전트.
Athena를 통해 RUM 데이터를 쿼리하고, 이상 감지, 성능 분석, 리포트 생성.
Next.js 14 Web UI를 통해 사용자와 채팅 인터페이스 제공.

## Key Files
- `agent.py` — 에이전트 메인. Strands Agent + MCP 도구 연결
- `requirements.txt` — Python 의존성 (strands-agents, boto3 등)
- `streamable_http_sigv4.py` — SigV4 인증 HTTP 클라이언트 유틸리티
- `web/` — Next.js 14 Web UI (에이전트 채팅 인터페이스)
- `web-app/` — 별도 배포 가능한 Next.js 앱
- `Dockerfile` — 에이전트 컨테이너 이미지
- `setup-agentcore.sh` — AgentCore 환경 설정 스크립트

## Key Commands
```bash
# 에이전트 실행
pip install -r requirements.txt
python3 agent.py

# Web UI 개발
cd web && npm install && npm run dev

# 컨테이너 빌드
docker build -t rum-agentcore .
```

## Rules
- AWS 자격증명은 IAM Role 또는 환경변수로 주입
- Bedrock 모델 ID는 환경변수로 설정
- MCP 도구는 `agent.py` 내 도구 목록으로 관리
- Athena 쿼리는 파티션 필터 필수 (비용 최적화)
- Web UI는 API Route를 통해 에이전트 호출 (직접 boto3 호출 금지)
