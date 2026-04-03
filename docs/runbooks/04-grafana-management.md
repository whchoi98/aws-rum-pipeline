# 런북: Grafana 워크스페이스 관리

## 개요
Amazon Managed Grafana 워크스페이스의 데이터소스, 대시보드, 사용자 관리.

## 데이터소스 및 대시보드 프로비저닝

```bash
export GRAFANA_URL="https://<workspace-id>.grafana-workspace.ap-northeast-2.amazonaws.com"
export GRAFANA_API_KEY="<service-account-token>"
export ACCOUNT_ID="<aws-account-id>"

./scripts/provision-grafana.sh
```

## 통합 대시보드 배포

```bash
python3 scripts/deploy-unified-dashboard.py
```

6개 섹션: KPI, 성능 개요, 크래시/에러, 리소스 분석, 모바일 바이탈, 사용자 세션.

## 사용자 관리 (SSO)

```bash
# SSO 사용자 목록
aws identitystore list-users \
  --identity-store-id <directory-id> \
  --region ap-northeast-2

# Grafana Admin 추가
USER_ID=$(aws identitystore list-users --identity-store-id <directory-id> \
  --query 'Users[?UserName==`username`].UserId | [0]' --output text --region ap-northeast-2)

aws grafana update-permissions --workspace-id <workspace-id> \
  --update-instruction-batch "[{
    \"action\":\"ADD\",
    \"role\":\"ADMIN\",
    \"users\":[{\"id\":\"$USER_ID\",\"type\":\"SSO_USER\"}]
  }]" --region ap-northeast-2
```

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 대시보드 데이터 없음 | 파티션 누락 | partition-repair Lambda 수동 실행 |
| Athena 쿼리 타임아웃 | 스캔 데이터 과다 | 파티션 필터 (year/month/day) 확인 |
| 데이터소스 연결 실패 | IAM 권한 | Grafana 역할에 Athena/Glue/S3 권한 확인 |
| 대시보드 로딩 느림 | 쿼리 비효율 | Athena 워크그룹 바이트 스캔 제한 확인 |
