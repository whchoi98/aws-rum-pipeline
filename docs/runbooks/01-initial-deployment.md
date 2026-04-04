<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: 초기 인프라 배포

### 개요
Terraform 또는 CDK로 RUM Pipeline 전체 인프라를 처음 배포하는 절차.

### 사전 조건
- AWS CLI v2+ 인증 완료 (`aws sts get-caller-identity`)
- Terraform >= 1.5 또는 Node.js >= 18 (CDK)
- ap-northeast-2 리전 접근 권한

### 절차

#### Option A: Terraform

```bash
# 1. 원격 상태 저장소 확인
aws s3 ls s3://rum-pipeline-terraform-state/ 2>/dev/null || \
  aws s3 mb s3://rum-pipeline-terraform-state --region ap-northeast-2

# 2. tfvars 설정
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# terraform.tfvars에 vpc_id, public_subnet_ids, agentcore_endpoint_arn 입력

# 3. 배포
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. 출력값 확인
terraform output
```

#### Option B: CDK

```bash
cd cdk && npm install
npx cdk bootstrap   # 최초 1회
npx cdk deploy \
  -c vpcId=vpc-xxx \
  -c publicSubnetIds='["subnet-aaa","subnet-bbb"]' \
  -c agentcoreEndpointArn='arn:aws:bedrock-agentcore:...'
```

#### 배포 후 검증

```bash
# API 엔드포인트 응답 확인
API_URL=$(cd terraform && terraform output -raw api_endpoint)
curl -s -o /dev/null -w "%{http_code}" "${API_URL}/v1/events"
# 403 (인증 필요) 또는 401 → 정상

# API Key 설정
aws ssm put-parameter \
  --name /rum-pipeline/dev/api-keys \
  --value "<secure-key>" \
  --type SecureString \
  --overwrite

# E2E 테스트
bash scripts/test-ingestion.sh "${API_URL}" "<api-key>"
```

### 롤백
```bash
cd terraform && terraform destroy   # 또는 npx cdk destroy
```

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: Initial Infrastructure Deployment

### Overview
Procedure for deploying the entire RUM Pipeline infrastructure for the first time using Terraform or CDK.

### Prerequisites
- AWS CLI v2+ authenticated (`aws sts get-caller-identity`)
- Terraform >= 1.5 or Node.js >= 18 (CDK)
- Access permissions for ap-northeast-2 region

### Procedure

#### Option A: Terraform

```bash
# 1. Verify remote state store
aws s3 ls s3://rum-pipeline-terraform-state/ 2>/dev/null || \
  aws s3 mb s3://rum-pipeline-terraform-state --region ap-northeast-2

# 2. Configure tfvars
cp terraform/terraform.tfvars.example terraform/terraform.tfvars
# Enter vpc_id, public_subnet_ids, agentcore_endpoint_arn in terraform.tfvars

# 3. Deploy
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan

# 4. Verify outputs
terraform output
```

#### Option B: CDK

```bash
cd cdk && npm install
npx cdk bootstrap   # First time only
npx cdk deploy \
  -c vpcId=vpc-xxx \
  -c publicSubnetIds='["subnet-aaa","subnet-bbb"]' \
  -c agentcoreEndpointArn='arn:aws:bedrock-agentcore:...'
```

#### Post-Deployment Verification

```bash
# Verify API endpoint response
API_URL=$(cd terraform && terraform output -raw api_endpoint)
curl -s -o /dev/null -w "%{http_code}" "${API_URL}/v1/events"
# 403 (auth required) or 401 → normal

# Set API Key
aws ssm put-parameter \
  --name /rum-pipeline/dev/api-keys \
  --value "<secure-key>" \
  --type SecureString \
  --overwrite

# E2E test
bash scripts/test-ingestion.sh "${API_URL}" "<api-key>"
```

### Rollback
```bash
cd terraform && terraform destroy   # or npx cdk destroy
```

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
