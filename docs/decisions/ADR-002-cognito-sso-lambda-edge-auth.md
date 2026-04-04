<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

# ADR-002: CloudFront Lambda@Edge + Cognito SSO 인증

## Status
Accepted

## Context
Agent UI가 CloudFront를 통해 공개 인터넷에 노출되어 있으나 인증이 없어,
누구나 Bedrock/Athena를 호출할 수 있는 보안 문제가 있음.
기존 Grafana에서 AWS IAM Identity Center (SSO)를 사용 중이므로 동일한 SSO로 통합 필요.

## Decision
- CloudFront viewer-request에 Lambda@Edge를 연결하여 모든 요청을 JWT 검증
- Cognito User Pool + SSO Identity Provider로 인증
- Authorization Code + PKCE 플로우 사용
- JWT의 `sub` 클레임을 `x-user-sub` 헤더로 Origin에 전달
- Next.js chat route에서 `x-user-sub`를 AgentCore Memory의 `session_id`로 사용하여 사용자별 대화 히스토리 분리

## Consequences
- **장점**: 인프라 레벨 인증 (앱 코드 변경 최소), SSO 통합, 사용자별 메모리 분리
- **단점**: Lambda@Edge는 us-east-1 배포 필수, 환경변수 사용 불가 (config.json 번들)
- **보안**: JWT HttpOnly 쿠키, PKCE, CloudFront-only ALB 접근으로 다중 보호

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

# ADR-002: CloudFront Lambda@Edge + Cognito SSO Authentication

## Status
Accepted

## Context
The Agent UI is exposed to the public internet via CloudFront without authentication,
creating a security vulnerability where anyone can invoke Bedrock/Athena.
Since the existing Grafana workspace already uses AWS IAM Identity Center (SSO), integration with the same SSO is required.

## Decision
- Attach Lambda@Edge to the CloudFront viewer-request to validate JWTs on every request
- Authenticate via Cognito User Pool + SSO Identity Provider
- Use the Authorization Code + PKCE flow
- Forward the JWT `sub` claim to the Origin as the `x-user-sub` header
- In the Next.js chat route, use `x-user-sub` as the AgentCore Memory `session_id` to isolate per-user conversation history

## Consequences
- **Pros**: Infrastructure-level authentication (minimal app code changes), SSO integration, per-user memory isolation
- **Cons**: Lambda@Edge must be deployed in us-east-1; environment variables cannot be used (config.json must be bundled)
- **Security**: Multi-layered protection via JWT HttpOnly cookies, PKCE, and CloudFront-only ALB access

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
