<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Lambda Module

### Role
RUM Pipeline의 Python 3.12 Lambda 함수들.
각 함수는 독립된 디렉토리로 관리되며 자체 requirements.txt와 pytest 테스트 보유.

### Functions

| 함수 | 트리거 | 역할 |
|------|--------|------|
| `authorizer/` | API Gateway Lambda Authorizer | JWT/API Key 검증 |
| `ingest/` | API Gateway HTTP Integration | HTTP → Firehose 포워딩 |
| `transform/` | Firehose Data Transformation | JSON 정규화, 스키마 검증 |
| `partition-repair/` | EventBridge (스케줄) | Glue 파티션 MSCK REPAIR |
| `athena-query/` | API Gateway or direct invoke | Athena 쿼리 실행/결과 반환 |
| `edge-auth/` | CloudFront Lambda@Edge (viewer-request) | Cognito JWT 검증, SSO 리다이렉트 (Node.js 20) |

### Key Files (per function)
- `handler.py` — Lambda 핸들러 진입점
- `test_handler.py` — pytest 테스트
- `requirements.txt` — 함수별 의존성

### Rules
- 각 함수 독립 배포 가능 (공유 레이어 최소화)
- 환경변수로 설정 주입 (하드코딩 금지)
- `python3 -m pytest test_handler.py -v` 로 테스트
- boto3 호출은 mock 처리 (moto 또는 unittest.mock)
- 에러는 CloudWatch Logs로 구조화 로깅 (JSON)
- IAM 최소 권한 원칙 적용

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Lambda Module

### Role
Python 3.12 Lambda functions for the RUM Pipeline.
Each function is managed in its own directory with its own requirements.txt and pytest tests.

### Functions

| Function | Trigger | Role |
|----------|---------|------|
| `authorizer/` | API Gateway Lambda Authorizer | JWT/API Key validation |
| `ingest/` | API Gateway HTTP Integration | HTTP → Firehose forwarding |
| `transform/` | Firehose Data Transformation | JSON normalization, schema validation |
| `partition-repair/` | EventBridge (scheduled) | Glue partition MSCK REPAIR |
| `athena-query/` | API Gateway or direct invoke | Athena query execution/result retrieval |
| `edge-auth/` | CloudFront Lambda@Edge (viewer-request) | Cognito JWT validation, SSO redirect (Node.js 20) |

### Key Files (per function)
- `handler.py` — Lambda handler entry point
- `test_handler.py` — pytest tests
- `requirements.txt` — Per-function dependencies

### Rules
- Each function is independently deployable (minimize shared layers)
- Configuration injected via environment variables (no hardcoding)
- Test with `python3 -m pytest test_handler.py -v`
- boto3 calls must be mocked (moto or unittest.mock)
- Errors logged as structured JSON to CloudWatch Logs
- Least-privilege IAM principle applied

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
