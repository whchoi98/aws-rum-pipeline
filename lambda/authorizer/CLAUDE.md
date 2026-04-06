<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Authorizer Lambda

### Role
API Gateway Lambda Authorizer -- `x-api-key` 헤더를 SSM Parameter Store에 저장된 키 목록과 비교하여 요청을 인가/거부.

### Key Files
| 파일 | 역할 |
|------|------|
| `handler.py` | x-api-key 헤더 검증, SSM에서 유효 키 조회 (5분 인메모리 캐시) |
| `test_handler.py` | pytest 테스트 (허용/거부/캐시/SSM 장애 시나리오) |

### Environment Variables
| 변수 | 용도 |
|------|------|
| `SSM_PARAMETER_NAME` | 유효 API 키가 저장된 SSM Parameter Store 경로 (쉼표 구분) |

### Key Commands
```bash
cd lambda/authorizer && python3 -m pytest test_handler.py -v
```

### Rules
- SSM 값은 쉼표로 구분된 API 키 문자열 (예: `key1,key2,key3`)
- 인메모리 캐시 TTL 300초 -- SSM 호출 비용 및 지연 최소화
- SSM 호출 실패 시 `{"isAuthorized": false}` 반환 (fail-closed)
- 빈 키 또는 누락된 헤더는 즉시 거부 (SSM 조회 없음)
- IAM: `ssm:GetParameter` 권한 필요 (해당 파라미터 ARN에 대해)
- 응답 형식은 API Gateway HTTP API v2 Authorizer 페이로드 포맷

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Authorizer Lambda

### Role
API Gateway Lambda Authorizer -- validates the `x-api-key` header against a list of keys stored in SSM Parameter Store.

### Key Files
| File | Role |
|------|------|
| `handler.py` | Validates x-api-key header, fetches valid keys from SSM (5-min in-memory cache) |
| `test_handler.py` | pytest tests (allow/deny/cache/SSM failure scenarios) |

### Environment Variables
| Variable | Purpose |
|----------|---------|
| `SSM_PARAMETER_NAME` | SSM Parameter Store path containing valid API keys (comma-separated) |

### Key Commands
```bash
cd lambda/authorizer && python3 -m pytest test_handler.py -v
```

### Rules
- SSM value is a comma-separated string of API keys (e.g., `key1,key2,key3`)
- In-memory cache TTL is 300 seconds -- minimizes SSM call cost and latency
- SSM call failure returns `{"isAuthorized": false}` (fail-closed design)
- Empty or missing key header is rejected immediately (no SSM lookup)
- IAM: requires `ssm:GetParameter` permission on the target parameter ARN
- Response format follows API Gateway HTTP API v2 Authorizer payload format

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
