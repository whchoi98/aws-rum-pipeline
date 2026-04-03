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
