# Edge Auth Lambda

## Role
CloudFront viewer-request에서 실행되는 Lambda@Edge 인증 함수.
Cognito JWT를 검증하고, 미인증 요청을 Cognito Hosted UI로 리다이렉트.

## Key Files
| 파일 | 역할 |
|------|------|
| `index.js` | 메인 핸들러 (JWT 검증, 토큰 교환, 로그아웃) |
| `config.json` | 환경 설정 (Terraform이 배포 시 자동 생성) |
| `config.json.example` | 설정 파일 예시 |

## 동작 흐름
1. `/auth/callback?code=xxx` → Cognito Token Endpoint에서 토큰 교환 → 쿠키 설정
2. `/auth/logout` → 쿠키 삭제 → Cognito 로그아웃
3. 기타 요청 → `id_token` 쿠키에서 JWT 검증 → `x-user-sub` 헤더 주입

## Rules
- Lambda@Edge는 환경변수 사용 불가 → config.json 필수
- config.json은 Terraform이 `local_file`로 자동 생성 (수동 생성 금지)
- JWKS는 메모리에 1시간 캐시 (콜드스타트 성능)
- 순수 Node.js만 사용 (외부 패키지 없음)
- viewer-request 타임아웃 최대 5초
