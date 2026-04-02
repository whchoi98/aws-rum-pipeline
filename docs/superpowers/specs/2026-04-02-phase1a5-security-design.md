# Phase 1a.5 — Security Design (Lambda Authorizer + WAF)

**Date:** 2026-04-02
**Status:** Approved
**Depends on:** Phase 1a Infrastructure (deployed)

## 1. Overview

Phase 1a에서 배포된 RUM 파이프라인 API가 현재 인증 없이 공개 상태이다.
Phase 1a.5는 Lambda Authorizer(API Key 검증)와 WAF(Rate Limiting + Bot Control)를 추가하여
무단 접근과 악성 트래픽을 차단한다.

### Goals

- API Key 기반 인증으로 무단 접근 차단
- WAF Rate-based Rule로 IP 단위 rate limiting
- AWS Managed Bot Control로 봇 트래픽 차단
- 기존 파이프라인(Ingest Lambda, Firehose, S3) 코드 변경 없음

### Non-Goals

- JWT/OAuth 기반 사용자 인증 (RUM SDK는 API Key로 충분)
- 셀프서비스 API Key 발급 포털
- CloudFront 배포 (현재 단일 리전 dev 환경)
- per-key rate limiting (WAF IP-level로 충분)

## 2. Architecture

```
SDK (x-api-key 헤더 포함)
    | HTTPS
    v
WAF WebACL
    |- Rate-based Rule: IP당 2000 req / 5분
    |- Bot Control: 알려진 봇 차단 (Common level)
    '- 통과
         |
         v
HTTP API Gateway
    |
    v
Lambda Authorizer (REQUEST type)
    |- x-api-key 헤더 추출
    |- SSM Parameter Store에서 유효 키 조회 (5분 캐싱)
    |- 유효 -> Allow (isAuthorized: true)
    '- 무효 -> Deny (isAuthorized: false, 403)
         |
         v (Allow)
Ingest Lambda -> Firehose (기존 파이프라인, 변경 없음)
```

### Key Decisions

| 결정 | 선택 | 근거 |
|------|------|------|
| Rate limiting | WAF Rate-based Rule | 인프라 레벨 차단 -> Lambda 호출 비용 절감 |
| API Key 저장 | SSM Parameter Store | 무료 (Standard tier), Terraform 관리 용이 |
| WAF 규칙 | Rate-based + Bot Control | Bot Control은 ~$10/월로 자동화된 봇 방어 |
| Key 범위 | 환경별 단일 키 | dev/staging/prod 각 1개. 현재 규모에 충분 |
| Authorizer 타입 | REQUEST (HTTP API v2) | 헤더 접근 필요, 간단한 응답 형식 지원 |

## 3. Terraform Module Structure

### New Module: `security`

```
terraform/modules/security/
    main.tf         <- WAF WebACL + Lambda Authorizer + IAM
    variables.tf
    outputs.tf
```

### Modified Module: `api-gateway`

- `aws_apigatewayv2_authorizer` 리소스 추가
- Route에 `authorization_type = "CUSTOM"` + authorizer 연결
- `aws_wafv2_web_acl_association` 리소스 추가

### New Lambda: `lambda/authorizer/`

```
lambda/authorizer/
    handler.py
    test_handler.py
```

### Dependency Chain

```
security (WAF + Authorizer Lambda 생성)
    | outputs: authorizer_invoke_arn, authorizer_function_name, waf_acl_arn
    v
api-gateway (authorizer 등록 + WAF association)
    |
    v
firehose, s3, glue (변경 없음)
```

### Root main.tf Changes

```hcl
module "security" {
  source            = "./modules/security"
  project_name      = var.project_name
  environment       = var.environment
  api_execution_arn = module.api_gateway.api_execution_arn
  tags              = { Component = "security" }
}
```

`api_gateway` 모듈에 authorizer/WAF 관련 변수 전달 추가.

## 4. Lambda Authorizer Detail

### Configuration

| 속성 | 값 |
|------|-----|
| Runtime | Python 3.12 |
| Memory | 128 MB |
| Timeout | 10 seconds |
| Handler | handler.handler |

### Logic

1. `event["headers"]`에서 `x-api-key` 추출
2. 키가 없으면 `{"isAuthorized": false}` 반환
3. SSM Parameter Store에서 유효 키 목록 조회 (글로벌 변수로 5분 캐싱)
4. 키가 유효하면 `{"isAuthorized": true, "context": {"apiKeyId": "<key-prefix>"}}` 반환
5. 키가 무효하면 `{"isAuthorized": false}` 반환

### SSM Parameter

- **Path:** `/rum-pipeline/{environment}/api-keys`
- **Value:** 쉼표 구분 키 목록 (예: `"rum-dev-abc123,rum-dev-def456"`)
- **Type:** SecureString
- Terraform `aws_ssm_parameter` 리소스로 초기 키 생성 (random_password)

### Caching Strategy

이중 캐싱으로 SSM 호출 최소화:

1. **API Gateway Authorizer 캐시:** `resultTtlInSeconds = 300` (동일 API key로 5분간 Authorizer Lambda 호출 안 함)
2. **Lambda 인메모리 캐시:** 글로벌 변수로 SSM 응답 5분간 보관 (cold start 시에만 SSM 호출)

### Key Rotation (무중단)

1. SSM Parameter에 새 키 추가 (쉼표 구분)
2. SDK에서 새 키로 전환
3. SSM Parameter에서 기존 키 제거
4. Authorizer 캐시 만료 (최대 5분) 후 완전 적용

## 5. WAF WebACL Detail

### Configuration

| 속성 | 값 |
|------|-----|
| Scope | REGIONAL |
| Default Action | Allow |
| CloudWatch Metrics | 활성화 |
| Sampled Requests | 활성화 |

### Rules (Priority Order)

**Priority 0 — Rate-based Rule:**
- IP당 2000 requests / 5분
- 초과 시 자동 차단 (Block)
- 임계값 이하로 내려가면 자동 해제
- CloudWatch metric: `RumRateLimitRule`

**Priority 1 — AWS Managed Bot Control:**
- Level: Common (기본 봇 탐지)
- Verified bots (Googlebot 등): 허용
- Known bad bots: 차단
- CloudWatch metric: `RumBotControlRule`

**Priority 2 — Default:**
- Action: Allow (나머지 트래픽 통과)

### Cost Estimate

| 항목 | 월 비용 |
|------|---------|
| WebACL | $5.00 |
| Rate-based Rule (1개) | $1.00 |
| Bot Control Managed Rule | $10.00 |
| Request 처리 (~500만 req) | ~$3.00 |
| **합계** | **~$19.00** |

## 6. API Gateway Changes

### New Resources

- `aws_apigatewayv2_authorizer` — Lambda Authorizer 등록
  - `authorizer_type = "REQUEST"`
  - `authorizer_uri` = security 모듈의 authorizer Lambda invoke ARN
  - `authorizer_payload_format_version = "2.0"`
  - `authorizer_result_ttl_in_seconds = 300`
  - `identity_sources = ["$request.header.x-api-key"]`

- `aws_wafv2_web_acl_association` — WAF를 API Stage에 연결
  - `resource_arn` = API Stage ARN
  - `web_acl_arn` = security 모듈의 WAF ACL ARN

### Modified Resources

- `aws_apigatewayv2_route.post_events` — `authorization_type = "CUSTOM"`, `authorizer_id` 추가
- `aws_apigatewayv2_route.post_beacon` — `authorization_type = "CUSTOM"`, `authorizer_id` 추가

### CORS

현재 `allow_headers`에 `x-api-key`가 이미 포함되어 있어 CORS 변경 불필요.
`allowed_origins`는 Phase 1b (Web SDK)에서 실제 도메인으로 제한 예정.

### New Lambda Permission

- Authorizer Lambda에 대한 `apigateway.amazonaws.com` invoke 권한 추가

## 7. Testing

### Unit Tests (lambda/authorizer/test_handler.py)

| 테스트 케이스 | 검증 |
|---------------|------|
| 유효한 API key | `isAuthorized: true` 반환 |
| 무효한 API key | `isAuthorized: false` 반환 |
| x-api-key 헤더 없음 | `isAuthorized: false` 반환 |
| 빈 문자열 API key | `isAuthorized: false` 반환 |
| SSM 캐싱 동작 | 두 번째 호출 시 SSM 미호출 확인 |
| SSM 장애 시 | 에러 로깅 + `isAuthorized: false` (fail-closed) |

### Integration Tests

| 테스트 | 검증 |
|--------|------|
| 유효 키로 POST /v1/events | 200 응답 + Firehose 전달 |
| 무효 키로 POST /v1/events | 403 응답 |
| 키 없이 POST /v1/events | 403 응답 |
| 유효 키로 POST /v1/events/beacon | 200 응답 |
| 기존 E2E 테스트 (키 추가) | 회귀 없음 확인 |

### WAF 검증 (수동)

- Rate limit 초과 테스트: 짧은 시간에 대량 요청 → 429/403 확인
- WAF CloudWatch 메트릭에서 BlockedRequests 확인

## 8. Rollback Plan

모든 보안 리소스는 `security` 모듈에 격리되어 있으므로:

1. `api-gateway` 모듈에서 authorizer/WAF 연결 제거
2. `security` 모듈 호출 제거
3. `terraform apply` → 기존 상태 복원

기존 Ingest Lambda 코드 변경이 없으므로 롤백 시 데이터 파이프라인에 영향 없음.
