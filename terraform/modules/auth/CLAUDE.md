# Auth Module

## Role
Agent UI 접근을 위한 Cognito SSO 인증 인프라.
Lambda@Edge로 CloudFront에서 JWT 검증, 미인증 요청은 Cognito Hosted UI로 리다이렉트.

## Key Files
| 파일 | 역할 |
|------|------|
| `main.tf` | Cognito User Pool, App Client, SSO IdP, Lambda@Edge |
| `variables.tf` | 입력 변수 (project_name, cloudfront_domain, sso_metadata_url) |
| `outputs.tf` | user_pool_id, client_id, edge_auth_qualified_arn |

## Key Resources
- `aws_cognito_user_pool` — 에이전트 사용자 풀
- `aws_cognito_user_pool_client` — Authorization Code + PKCE
- `aws_cognito_identity_provider` — SSO SAML 연동 (조건부)
- `aws_lambda_function` — Lambda@Edge viewer-request (us-east-1)

## Rules
- Lambda@Edge는 반드시 us-east-1에 배포 (CloudFront 요구사항)
- Lambda@Edge는 환경변수 사용 불가 → config.json으로 설정 번들
- `publish = true` 필수 (Lambda@Edge는 버전 게시 필요)
- SSO 연동은 `sso_metadata_url` 변수가 비어있으면 비활성화
