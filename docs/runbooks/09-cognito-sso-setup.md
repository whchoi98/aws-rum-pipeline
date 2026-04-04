# 런북: Cognito SSO 설정 및 관리

## 개요
Agent UI 인증을 위한 Cognito User Pool + IAM Identity Center (SSO) 연동 설정 절차.
Lambda@Edge가 CloudFront에서 JWT를 검증하고, 미인증 요청을 Cognito Hosted UI로 리다이렉트.

## 사전 조건
- AWS IAM Identity Center (SSO) 활성화 및 사용자 생성 완료
- Agent UI CloudFront 배포 완료
- Terraform >= 1.5 또는 CDK

## 1. SSO SAML 메타데이터 URL 확인

```bash
# IAM Identity Center 인스턴스 확인
aws sso-admin list-instances --region ap-northeast-2

# SAML 메타데이터 URL 형식:
# https://portal.sso.<region>.amazonaws.com/saml/metadata/<instance-id>
```

## 2. Terraform 배포

```bash
cd terraform

# terraform.tfvars에 SSO 메타데이터 URL 추가
cat >> terraform.tfvars << 'EOF'
sso_metadata_url = "https://portal.sso.ap-northeast-2.amazonaws.com/saml/metadata/<instance-id>"
EOF

terraform plan -target=module.auth
terraform apply -target=module.auth

# CloudFront에 Lambda@Edge 연결
terraform plan -target=module.agent_ui
terraform apply -target=module.agent_ui
```

## 3. Cognito에 SSO Application 등록

SSO 측에서 Cognito를 SAML 앱으로 등록해야 합니다.

```bash
# Cognito User Pool ID 확인
POOL_ID=$(terraform output -raw auth_user_pool_id 2>/dev/null || \
  aws cognito-idp list-user-pools --max-results 10 --region ap-northeast-2 \
  --query "UserPools[?Name=='rum-pipeline-agent-users'].Id | [0]" --output text)

echo "User Pool ID: ${POOL_ID}"

# Cognito SAML 엔드포인트 (SSO 앱에 등록할 URL)
echo "ACS URL: https://rum-pipeline.auth.ap-northeast-2.amazoncognito.com/saml2/idpresponse"
echo "Entity ID: urn:amazon:cognito:sp:${POOL_ID}"
```

IAM Identity Center 콘솔에서:
1. **Applications** → **Add application** → **Custom SAML 2.0**
2. **ACS URL**: 위의 ACS URL 입력
3. **Entity ID**: 위의 Entity ID 입력
4. **Attribute mapping**: `email` → `${user:email}`, `name` → `${user:name}`
5. **Users/Groups**: 접근 허용할 사용자/그룹 할당

## 4. 검증

```bash
# CloudFront 도메인 확인
CF_DOMAIN=$(terraform output -raw agent_ui_cloudfront_url 2>/dev/null || \
  aws cloudfront list-distributions \
  --query "DistributionList.Items[?Comment=='RUM Agent UI'].DomainName | [0]" --output text)

# 브라우저에서 접근 → SSO 로그인 페이지로 리다이렉트 확인
echo "테스트 URL: https://${CF_DOMAIN}"

# curl로 리다이렉트 확인 (302 → Cognito Hosted UI)
curl -s -o /dev/null -w "%{http_code} → %{redirect_url}" "https://${CF_DOMAIN}/"
# 기대: 302 → https://rum-pipeline.auth.ap-northeast-2.amazoncognito.com/oauth2/authorize?...
```

## 5. 로그아웃 테스트

```bash
# 로그아웃 URL
echo "로그아웃: https://${CF_DOMAIN}/auth/logout"
# → 쿠키 삭제 → Cognito 로그아웃 → 홈 리다이렉트
```

## 6. 사용자 관리

```bash
# Cognito User Pool 사용자 목록 (SSO 연동 사용자 포함)
aws cognito-idp list-users --user-pool-id ${POOL_ID} --region ap-northeast-2 \
  --query 'Users[].{Username:Username,Email:Attributes[?Name==`email`].Value|[0],Status:UserStatus}'

# 특정 사용자 비활성화
aws cognito-idp admin-disable-user \
  --user-pool-id ${POOL_ID} \
  --username "<username>" \
  --region ap-northeast-2

# 특정 사용자 재활성화
aws cognito-idp admin-enable-user \
  --user-pool-id ${POOL_ID} \
  --username "<username>" \
  --region ap-northeast-2
```

## 7. Lambda@Edge 로그 확인

Lambda@Edge 로그는 **사용자가 접근한 엣지 로케이션의 리전**에 생성됩니다.

```bash
# 서울 리전 로그 확인
aws logs filter-log-events \
  --log-group-name "/aws/lambda/us-east-1.rum-pipeline-edge-auth" \
  --start-time $(date -d '1 hour ago' +%s000) \
  --region ap-northeast-2 \
  --filter-pattern "ERROR" \
  --query 'events[].message' --output text

# 도쿄 리전 (일본에서 접근 시)
aws logs filter-log-events \
  --log-group-name "/aws/lambda/us-east-1.rum-pipeline-edge-auth" \
  --start-time $(date -d '1 hour ago' +%s000) \
  --region ap-northeast-1 \
  --filter-pattern "ERROR"
```

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 로그인 후 무한 리다이렉트 | Callback URL 불일치 | Cognito App Client의 callback URL과 CloudFront 도메인 일치 확인 |
| 403 after login | SAML attribute mapping 누락 | SSO 앱에서 email 매핑 확인 |
| JWT 검증 실패 | JWKS 캐시 만료 또는 User Pool ID 불일치 | config.json의 userPoolId 확인 |
| SSO 로그인 페이지 안 뜸 | Identity Provider 미설정 | `sso_metadata_url` 변수 확인, `terraform apply` 재실행 |
| 쿠키 설정 안 됨 | SameSite/Secure 설정 이슈 | HTTPS 접근 확인 (HTTP는 Secure 쿠키 불가) |
| 토큰 만료 후 재로그인 안 됨 | 쿠키 삭제 실패 | `/auth/logout` 경로로 명시적 로그아웃 후 재시도 |
