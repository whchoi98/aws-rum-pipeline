# CloudFront + Lambda@Edge + Cognito SSO 인증 + Per-User Memory 설계

**Date:** 2026-04-03
**Status:** Accepted

## 1. Overview

Agent UI (CloudFront → ALB → EC2)에 Cognito SSO 인증을 추가하고,
인증된 사용자별로 AgentCore Memory를 분리하여 대화 히스토리를 관리한다.

### Goals
- CloudFront 레벨에서 Lambda@Edge로 모든 요청을 인증
- 기존 AWS IAM Identity Center (SSO)와 Cognito User Pool 연동
- 사용자별 AgentCore Memory 분리 (session_id = user_sub)
- 미인증 접근 완전 차단

### Non-Goals
- 세션 리플레이 (Phase 2)
- 역할 기반 접근 제어 (RBAC) — 인증만, 인가는 추후
- 자체 로그인 UI 개발 (Cognito Hosted UI 사용)

## 2. Architecture

```
사용자 → CloudFront
           ├─ Lambda@Edge (viewer-request)
           │    ├─ /auth/callback → authorization code → token 교환 → Set-Cookie → 302 /
           │    ├─ JWT 쿠키 있음 → JWKS 검증 → x-user-sub 헤더 주입 → Origin
           │    └─ JWT 없음 → 302 Cognito Hosted UI
           │
           └─ Origin (ALB → EC2 Next.js)
                └─ x-user-sub 헤더에서 사용자 식별
                    └─ /api/chat → session_id = user_sub → AgentCore Memory
```

## 3. Components

### 3.1 Cognito User Pool + SSO Identity Provider

- **User Pool**: `{project_name}-agent-users` (ap-northeast-2)
- **App Client**: Authorization Code Grant, PKCE 활성화, no client secret
- **Identity Provider**: SAML 또는 OIDC로 AWS IAM Identity Center 연동
- **Hosted UI 도메인**: `{project_name}.auth.ap-northeast-2.amazoncognito.com`
- **Callback URL**: `https://{cloudfront_domain}/auth/callback`
- **Logout URL**: `https://{cloudfront_domain}/`
- **Scopes**: openid, email, profile

### 3.2 Lambda@Edge (viewer-request)

- **런타임**: Node.js 20.x
- **배포 리전**: us-east-1 (Lambda@Edge 필수)
- **위치**: `lambda/edge-auth/`
- **환경 변수 불가** → SSM Parameter 또는 함수 코드에 설정 번들

**로직**:
1. `GET /auth/callback?code=xxx` → Cognito Token Endpoint에 code 교환 → id_token/access_token 쿠키 설정 → 302 /
2. `GET /auth/logout` → 쿠키 삭제 → Cognito Logout URL로 리다이렉트
3. 기타 요청 → 쿠키에서 `id_token` 추출 → JWKS로 검증 → `x-user-sub` 헤더 추가 → 요청 통과
4. 쿠키 없거나 검증 실패 → 302 Cognito Hosted UI (Authorization Code flow)

**JWT 검증**:
- Cognito JWKS URL에서 공개키 다운로드 (콜드스타트 시 1회, 캐시)
- `kid` 매칭 → RS256 서명 검증
- `exp`, `iss`, `aud` 클레임 검증
- 검증 통과 시 `sub` 클레임 추출

**쿠키 설정**:
- `id_token`: HttpOnly, Secure, SameSite=Lax, Path=/
- `access_token`: HttpOnly, Secure, SameSite=Lax, Path=/
- Max-Age: id_token의 exp - now (보통 1시간)

### 3.3 Next.js Chat Route 수정

**파일**: `agentcore/web-app/app/api/chat/route.ts`

변경사항:
- `request.headers.get('x-user-sub')` 로 사용자 ID 추출
- 없으면 401 반환
- Athena Query Lambda 호출 시 `session_id = user_sub` 전달
- Bedrock 호출 시 시스템 프롬프트에 사용자 컨텍스트 추가 (선택)

### 3.4 AgentCore Memory 분리

기존 `agent.py`의 `MemoryHook`이 이미 `session_id` 기반:
- `memory_client.get_last_k_turns(memory_id, actor_id="user", session_id=user_sub, k=5)`
- `memory_client.create_event(memory_id, actor_id="user", session_id=user_sub, messages=[...])`

web-app chat route에서도 동일 패턴 적용:
- Lambda 호출 시 `session_id: user_sub` 전달

## 4. Infrastructure (Terraform)

### 새 모듈: `terraform/modules/auth/`

| 리소스 | 설명 |
|--------|------|
| `aws_cognito_user_pool` | 에이전트 사용자 풀 |
| `aws_cognito_user_pool_client` | App Client (Auth Code + PKCE) |
| `aws_cognito_user_pool_domain` | Hosted UI 도메인 |
| `aws_cognito_identity_provider` | SSO IdP 연동 |
| `aws_lambda_function` | Lambda@Edge (us-east-1) |
| `aws_iam_role` | Lambda@Edge 실행 역할 |
| `aws_cloudwatch_log_group` | Lambda 로그 |

### agent-ui 모듈 변경

CloudFront에 Lambda@Edge association 추가:
```hcl
lambda_function_association {
  event_type   = "viewer-request"
  lambda_arn   = var.edge_auth_qualified_arn  # 버전 포함 ARN
  include_body = false
}
```

## 5. Infrastructure (CDK)

### 새 Construct: `cdk/lib/constructs/auth.ts`

Cognito User Pool + App Client + Lambda@Edge를 포함.
Lambda@Edge는 us-east-1에 배포해야 하므로 `cloudfront.experimental.EdgeFunction` 사용.

### agent-ui Construct 변경

CloudFront Distribution의 defaultBehavior에 edgeLambdas 추가.

## 6. Data Flow (Per-User Memory)

```
1. 사용자 로그인 → Cognito → JWT (sub: "abc-123-def")
2. 채팅 요청 → Lambda@Edge → x-user-sub: "abc-123-def" → Next.js
3. Next.js → Athena Query Lambda (session_id: "abc-123-def")
4. AgentCore Memory → get_last_k_turns(session_id: "abc-123-def") → 이전 대화 로드
5. Bedrock 응답 → Memory.create_event(session_id: "abc-123-def") → 대화 저장
6. 다음 로그인 → 동일 sub → 이전 대화 히스토리 유지
```

## 7. Security

- JWT는 HttpOnly + Secure 쿠키로만 전달 (XSS 방어)
- Lambda@Edge에서 JWKS 검증 (위변조 방지)
- Origin은 ALB SG로 CloudFront만 접근 가능
- x-user-sub 헤더는 Lambda@Edge에서만 설정 (클라이언트 주입 불가)
- PKCE로 Authorization Code 탈취 방지
