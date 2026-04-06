<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Security Module

### Role
WAF WebACL, API Key 관리(SSM), Lambda Authorizer를 통해 RUM 파이프라인 API 보안을 담당.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_wafv2_web_acl` | REGIONAL WAF — IP 기반 Rate Limit + AWS Bot Control 관리형 규칙 |
| `random_password` | 32자 API Key 자동 생성 |
| `aws_ssm_parameter` | SecureString으로 API Key 저장 (`/{project}/{env}/api-keys`) |
| `aws_lambda_function.authorizer` | API Key 검증 Lambda Authorizer (SSM에서 키 조회) |
| `aws_iam_role.authorizer_lambda` | Authorizer Lambda IAM (CloudWatch Logs + SSM 읽기) |

### Input Variables
| 변수 | 설명 | 기본값 |
|------|------|--------|
| `environment` | 환경명 (dev, staging, prod) — SSM 경로에 사용 | - |
| `rate_limit` | WAF IP별 5분 윈도우 최대 요청 수 | 2000 |
| `lambda_source_dir` | Authorizer Lambda 소스 경로 | - |

### Rules
- SSM 파라미터 값은 `lifecycle { ignore_changes = [value] }` — 초기 생성 후 콘솔/CLI에서 수동 변경 가능
- WAF는 REGIONAL 스코프 — REST API 또는 ALB에만 직접 연결 가능 (HTTP API는 불가)
- Bot Control은 `COMMON` 검사 수준 사용 (TARGETED보다 비용 저렴)
- Authorizer Lambda는 `SSM_PARAMETER_NAME` 환경변수로 키 경로를 받음

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Security Module

### Role
Handles RUM pipeline API security via WAF WebACL, API Key management (SSM), and Lambda Authorizer.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_wafv2_web_acl` | REGIONAL WAF — IP-based Rate Limit + AWS Bot Control managed rule |
| `random_password` | Auto-generates a 32-character API key |
| `aws_ssm_parameter` | Stores API key as SecureString (`/{project}/{env}/api-keys`) |
| `aws_lambda_function.authorizer` | API Key validation Lambda Authorizer (reads keys from SSM) |
| `aws_iam_role.authorizer_lambda` | Authorizer Lambda IAM (CloudWatch Logs + SSM read) |

### Input Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `environment` | Environment name (dev, staging, prod) — used in SSM path | - |
| `rate_limit` | WAF max requests per 5-minute window per IP | 2000 |
| `lambda_source_dir` | Authorizer Lambda source path | - |

### Rules
- SSM parameter value has `lifecycle { ignore_changes = [value] }` — can be manually updated via console/CLI after initial creation
- WAF scope is REGIONAL — can only be directly associated with REST APIs or ALBs (not HTTP APIs)
- Bot Control uses `COMMON` inspection level (cheaper than TARGETED)
- Authorizer Lambda receives the key path via `SSM_PARAMETER_NAME` environment variable

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
