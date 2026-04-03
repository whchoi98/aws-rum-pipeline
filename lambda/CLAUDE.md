# Lambda Module

## Role
RUM Pipeline의 Python 3.12 Lambda 함수들.
각 함수는 독립된 디렉토리로 관리되며 자체 requirements.txt와 pytest 테스트 보유.

## Functions

| 함수 | 트리거 | 역할 |
|------|--------|------|
| `authorizer/` | API Gateway Lambda Authorizer | JWT/API Key 검증 |
| `ingest/` | API Gateway HTTP Integration | HTTP → Firehose 포워딩 |
| `transform/` | Firehose Data Transformation | JSON 정규화, 스키마 검증 |
| `partition-repair/` | EventBridge (스케줄) | Glue 파티션 MSCK REPAIR |
| `athena-query/` | API Gateway or direct invoke | Athena 쿼리 실행/결과 반환 |

## Key Files (per function)
- `handler.py` — Lambda 핸들러 진입점
- `test_handler.py` — pytest 테스트
- `requirements.txt` — 함수별 의존성

## Rules
- 각 함수 독립 배포 가능 (공유 레이어 최소화)
- 환경변수로 설정 주입 (하드코딩 금지)
- `python3 -m pytest test_handler.py -v` 로 테스트
- boto3 호출은 mock 처리 (moto 또는 unittest.mock)
- 에러는 CloudWatch Logs로 구조화 로깅 (JSON)
- IAM 최소 권한 원칙 적용
