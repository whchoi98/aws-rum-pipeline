<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## API Gateway Module

### Role
HTTP API Gateway와 Ingest Lambda를 관리하여 클라이언트 RUM 이벤트를 수신하고 Firehose로 전달.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_apigatewayv2_api` | HTTP API (CORS 설정 포함) |
| `aws_apigatewayv2_stage` | `$default` 스테이지 (자동 배포, 스로틀 설정) |
| `aws_apigatewayv2_route` (x2) | `POST /v1/events`, `POST /v1/events/beacon` 라우트 |
| `aws_apigatewayv2_authorizer` | REQUEST 타입 Lambda Authorizer (조건부, `enable_auth`) |
| `aws_apigatewayv2_integration` | Ingest Lambda AWS_PROXY 통합 |
| `aws_lambda_function.ingest` | HTTP 요청을 Firehose PutRecord로 변환 |
| `aws_lambda_permission` (x2) | API Gateway → Ingest Lambda, API Gateway → Authorizer Lambda 호출 권한 |

### Input Variables
| 변수 | 설명 | 기본값 |
|------|------|--------|
| `firehose_stream_name` / `firehose_stream_arn` | 대상 Firehose 스트림 | - |
| `lambda_source_dir` | Ingest Lambda 소스 경로 | - |
| `allowed_origins` | CORS 허용 오리진 | `["*"]` |
| `enable_auth` | Lambda Authorizer 활성화 여부 | `false` |
| `authorizer_invoke_arn` | Authorizer Lambda invoke ARN | `null` |

### Rules
- WAF WebACL은 HTTP API에 직접 연결 불가 — CloudFront 도입 시 연결 예정 (코드 주석 참조)
- `enable_auth`는 plan-time에 결정되어야 함 (동적 값 사용 불가)
- CORS는 `POST`, `OPTIONS` 메서드만 허용하며 `x-api-key` 헤더 포함
- 스로틀: burst 1000, rate 500 (기본 스테이지 설정)
- Authorizer 결과 TTL은 300초 (5분 캐싱)

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## API Gateway Module

### Role
Manages the HTTP API Gateway and Ingest Lambda to receive client RUM events and forward them to Firehose.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_apigatewayv2_api` | HTTP API (with CORS configuration) |
| `aws_apigatewayv2_stage` | `$default` stage (auto-deploy, throttle settings) |
| `aws_apigatewayv2_route` (x2) | `POST /v1/events`, `POST /v1/events/beacon` routes |
| `aws_apigatewayv2_authorizer` | REQUEST-type Lambda Authorizer (conditional, `enable_auth`) |
| `aws_apigatewayv2_integration` | Ingest Lambda AWS_PROXY integration |
| `aws_lambda_function.ingest` | Converts HTTP requests to Firehose PutRecord |
| `aws_lambda_permission` (x2) | API Gateway invoke permissions for Ingest and Authorizer Lambdas |

### Input Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `firehose_stream_name` / `firehose_stream_arn` | Target Firehose stream | - |
| `lambda_source_dir` | Ingest Lambda source path | - |
| `allowed_origins` | CORS allowed origins | `["*"]` |
| `enable_auth` | Enable Lambda Authorizer | `false` |
| `authorizer_invoke_arn` | Authorizer Lambda invoke ARN | `null` |

### Rules
- WAF WebACL cannot be associated directly with HTTP APIs — will be attached when CloudFront is introduced (see code comments)
- `enable_auth` must be known at plan-time (cannot use dynamic values)
- CORS allows only `POST`, `OPTIONS` methods with `x-api-key` header
- Throttling: burst 1000, rate 500 (default stage settings)
- Authorizer result TTL is 300 seconds (5-minute caching)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
