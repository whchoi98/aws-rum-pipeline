# 런북: API Key 로테이션

## 개요
SSM Parameter Store에 저장된 API Key를 무중단으로 교체하는 절차.
Authorizer Lambda 캐시 TTL이 300초이므로, 교체 후 5분 이내 전파 완료.

## 절차

```bash
# 1. 현재 키 확인
aws ssm get-parameter \
  --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text

# 2. 새 키 생성 (기존 키와 콤마 구분으로 병행 운영)
NEW_KEY=$(openssl rand -hex 16)
OLD_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text)

aws ssm put-parameter \
  --name /rum-pipeline/dev/api-keys \
  --value "${OLD_KEY},${NEW_KEY}" \
  --type SecureString \
  --overwrite

# 3. 클라이언트에 새 키 배포 (SDK, Simulator 등)
# → 5분 대기 (캐시 만료)

# 4. 새 키로 테스트
curl -X POST "${API_URL}/v1/events" \
  -H "x-api-key: ${NEW_KEY}" \
  -H "Content-Type: application/json" \
  -d '{"events":[{"event_type":"test","event_name":"key_rotation","timestamp":'"$(date +%s000)"'}]}'

# 5. 기존 키 제거
aws ssm put-parameter \
  --name /rum-pipeline/dev/api-keys \
  --value "${NEW_KEY}" \
  --type SecureString \
  --overwrite
```

## 긴급 키 무효화 (보안 사고 시)

```bash
# 즉시 빈 값으로 교체 → 모든 요청 거부
aws ssm put-parameter \
  --name /rum-pipeline/dev/api-keys \
  --value "REVOKED" \
  --type SecureString \
  --overwrite
# 5분 후 완전 차단 (캐시 만료)
```

## 검증
- CloudWatch에서 Authorizer Lambda 403 비율 확인
- API Gateway 4xx 메트릭 모니터링
