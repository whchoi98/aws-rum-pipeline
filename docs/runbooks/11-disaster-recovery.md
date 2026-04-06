<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: 재해 복구 (Disaster Recovery)

### 개요
RUM Pipeline 구성 요소 장애 시 복구 절차.
Terraform 상태, S3 데이터, Firehose, Lambda, Grafana, Agent UI, Cognito 복구를 다룬다.

### 사전 조건
- AWS CLI v2+ 인증 완료 (관리자 권한 필요)
- Terraform >= 1.5 설치
- 원격 상태 저장소 접근 권한 (`s3://rum-pipeline-terraform-state/`)
- DynamoDB 락 테이블 접근 권한

### 절차

#### 1. Terraform 상태 복구

```bash
# S3 상태 파일 버전 목록 확인 (버전 관리 활성화 필수)
aws s3api list-object-versions \
  --bucket rum-pipeline-terraform-state \
  --prefix terraform.tfstate \
  --query 'Versions[0:5].{VersionId:VersionId,LastModified:LastModified,Size:Size}'

# 이전 버전 복원
aws s3api get-object \
  --bucket rum-pipeline-terraform-state \
  --key terraform.tfstate \
  --version-id <version-id> \
  /tmp/terraform.tfstate.backup

# DynamoDB 락 해제 (락이 걸린 경우)
aws dynamodb delete-item \
  --table-name rum-pipeline-terraform-lock \
  --key '{"LockID":{"S":"rum-pipeline-terraform-state/terraform.tfstate-md5"}}'
```

#### 2. S3 데이터 레이크 복구

```bash
# S3 버전 관리로 삭제된 객체 복원
aws s3api list-object-versions \
  --bucket rum-pipeline-raw-data \
  --prefix "year=2026/" \
  --query 'DeleteMarkers[?IsLatest==`true`].Key'

# 개별 객체 복원 (삭제 마커 제거)
aws s3api delete-object \
  --bucket rum-pipeline-raw-data \
  --key "<object-key>" \
  --version-id "<delete-marker-version-id>"

# 크로스 리전 복제 상태 확인 (설정된 경우)
aws s3api get-bucket-replication \
  --bucket rum-pipeline-raw-data
```

#### 3. Firehose 전송 실패 복구

```bash
# 에러 버킷 확인
aws s3 ls s3://rum-pipeline-raw-data/errors/ --recursive | tail -20

# Firehose 상태 확인
aws firehose describe-delivery-stream \
  --delivery-stream-name rum-pipeline-firehose \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'

# 실패한 레코드 재처리 — 에러 파일을 다시 Firehose로 전송
aws s3 cp s3://rum-pipeline-raw-data/errors/<error-file> /tmp/error-records.json
# 레코드를 파싱하여 Firehose로 재전송
```

#### 4. Lambda 함수 복구

```bash
# Lambda 함수 상태 확인
for fn in rum-ingest rum-transform rum-authorizer rum-partition-repair rum-athena-query; do
  echo "=== $fn ==="
  aws lambda get-function --function-name $fn --query 'Configuration.State'
done

# Terraform으로 재배포
cd terraform
terraform apply -target=module.api_gateway -target=module.security
```

#### 5. Grafana 워크스페이스 복구

```bash
# 워크스페이스 상태 확인
aws grafana list-workspaces --query 'workspaces[?name==`rum-pipeline`].{id:id,status:status}'

# 프로비저닝 스크립트 실행
bash scripts/provision-grafana.sh
```

#### 6. Agent UI (EC2) 복구

```bash
# EC2 인스턴스 상태 확인
aws ec2 describe-instances \
  --filters "Name=tag:project,Values=rum-pipeline" "Name=tag:component,Values=agent-ui" \
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name}'

# Terraform으로 재생성
cd terraform && terraform apply -target=module.agent_ui

# CloudFront 캐시 무효화
aws cloudfront create-invalidation \
  --distribution-id <distribution-id> \
  --paths "/*"
```

#### 7. Cognito 사용자 풀 복구

```bash
# 사용자 풀 상태 확인
aws cognito-idp describe-user-pool \
  --user-pool-id <user-pool-id> \
  --query 'UserPool.Status'

# 사용자 목록 백업 (정기적으로 수행 권장)
aws cognito-idp list-users \
  --user-pool-id <user-pool-id> \
  --output json > /tmp/cognito-users-backup.json
```

### 에스컬레이션

| 단계 | 담당 | 연락 방법 |
|------|------|-----------|
| L1 | DevOps 온콜 | Slack #rum-pipeline-alerts |
| L2 | 인프라 팀 리드 | 팀 내부 연락망 |
| L3 | AWS 기술 지원 | AWS Support Console |

### 롤백
각 구성 요소별 롤백은 해당 섹션의 Terraform 명령을 사용한다.
전체 환경 롤백: `cd terraform && terraform destroy && terraform apply`

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: Disaster Recovery

### Overview
Recovery procedures for RUM Pipeline component failures.
Covers Terraform state, S3 data, Firehose, Lambda, Grafana, Agent UI, and Cognito recovery.

### Prerequisites
- AWS CLI v2+ authenticated (admin permissions required)
- Terraform >= 1.5 installed
- Access to remote state store (`s3://rum-pipeline-terraform-state/`)
- Access to DynamoDB lock table

### Procedure

#### 1. Terraform State Recovery

```bash
# List state file versions (versioning must be enabled)
aws s3api list-object-versions \
  --bucket rum-pipeline-terraform-state \
  --prefix terraform.tfstate \
  --query 'Versions[0:5].{VersionId:VersionId,LastModified:LastModified,Size:Size}'

# Restore previous version
aws s3api get-object \
  --bucket rum-pipeline-terraform-state \
  --key terraform.tfstate \
  --version-id <version-id> \
  /tmp/terraform.tfstate.backup

# Release DynamoDB lock (if stuck)
aws dynamodb delete-item \
  --table-name rum-pipeline-terraform-lock \
  --key '{"LockID":{"S":"rum-pipeline-terraform-state/terraform.tfstate-md5"}}'
```

#### 2. S3 Data Lake Recovery

```bash
# Restore deleted objects using S3 versioning
aws s3api list-object-versions \
  --bucket rum-pipeline-raw-data \
  --prefix "year=2026/" \
  --query 'DeleteMarkers[?IsLatest==`true`].Key'

# Restore individual objects (remove delete markers)
aws s3api delete-object \
  --bucket rum-pipeline-raw-data \
  --key "<object-key>" \
  --version-id "<delete-marker-version-id>"

# Check cross-region replication status (if configured)
aws s3api get-bucket-replication \
  --bucket rum-pipeline-raw-data
```

#### 3. Firehose Delivery Failure Recovery

```bash
# Check error bucket
aws s3 ls s3://rum-pipeline-raw-data/errors/ --recursive | tail -20

# Check Firehose status
aws firehose describe-delivery-stream \
  --delivery-stream-name rum-pipeline-firehose \
  --query 'DeliveryStreamDescription.DeliveryStreamStatus'

# Reprocess failed records — re-send error files to Firehose
aws s3 cp s3://rum-pipeline-raw-data/errors/<error-file> /tmp/error-records.json
# Parse records and re-send to Firehose
```

#### 4. Lambda Function Recovery

```bash
# Check Lambda function status
for fn in rum-ingest rum-transform rum-authorizer rum-partition-repair rum-athena-query; do
  echo "=== $fn ==="
  aws lambda get-function --function-name $fn --query 'Configuration.State'
done

# Redeploy via Terraform
cd terraform
terraform apply -target=module.api_gateway -target=module.security
```

#### 5. Grafana Workspace Recovery

```bash
# Check workspace status
aws grafana list-workspaces --query 'workspaces[?name==`rum-pipeline`].{id:id,status:status}'

# Run provisioning script
bash scripts/provision-grafana.sh
```

#### 6. Agent UI (EC2) Recovery

```bash
# Check EC2 instance status
aws ec2 describe-instances \
  --filters "Name=tag:project,Values=rum-pipeline" "Name=tag:component,Values=agent-ui" \
  --query 'Reservations[].Instances[].{Id:InstanceId,State:State.Name}'

# Recreate via Terraform
cd terraform && terraform apply -target=module.agent_ui

# Invalidate CloudFront cache
aws cloudfront create-invalidation \
  --distribution-id <distribution-id> \
  --paths "/*"
```

#### 7. Cognito User Pool Recovery

```bash
# Check user pool status
aws cognito-idp describe-user-pool \
  --user-pool-id <user-pool-id> \
  --query 'UserPool.Status'

# Backup user list (recommended to run periodically)
aws cognito-idp list-users \
  --user-pool-id <user-pool-id> \
  --output json > /tmp/cognito-users-backup.json
```

### Escalation

| Level | Owner | Contact |
|-------|-------|---------|
| L1 | DevOps On-Call | Slack #rum-pipeline-alerts |
| L2 | Infrastructure Team Lead | Internal contact list |
| L3 | AWS Technical Support | AWS Support Console |

### Rollback
Use the Terraform commands in each section for per-component rollback.
Full environment rollback: `cd terraform && terraform destroy && terraform apply`

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
