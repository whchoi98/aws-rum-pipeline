<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: Glue 테이블 스키마 마이그레이션

### 개요
RUM 이벤트 형식 변경 시 Glue 테이블 스키마를 안전하게 마이그레이션하는 절차.
기존 Parquet 파일과의 하위 호환성을 유지하면서 스키마를 업데이트한다.

### 사전 조건
- AWS CLI v2+ 인증 완료 (`aws sts get-caller-identity`)
- Terraform >= 1.5 설치
- Athena 쿼리 실행 권한
- Glue 데이터베이스 `rum_pipeline_db` 접근 권한

### 절차

#### 1. 현재 스키마 확인

```bash
# 현재 Glue 테이블 스키마 조회
aws glue get-table \
  --database-name rum_pipeline_db \
  --name rum_events \
  --query 'Table.StorageDescriptor.Columns' \
  --output table

# 현재 파티션 키 확인
aws glue get-table \
  --database-name rum_pipeline_db \
  --name rum_events \
  --query 'Table.PartitionKeys' \
  --output table
```

#### 2. Terraform에서 스키마 수정

```bash
# glue-catalog 모듈 편집
# terraform/modules/glue-catalog/main.tf 에서 columns 블록 수정
# 예: 새 컬럼 추가 시 columns 목록 끝에 추가 (하위 호환성 유지)

cd terraform
terraform fmt -recursive
terraform validate
```

#### 3. 변경 사항 검증

```bash
cd terraform
terraform plan -target=module.glue_catalog 2>&1 | tee /tmp/glue-plan.txt
# "~ update in-place" 확인 — "destroy" 가 있으면 중단!
```

#### 4. 스키마 적용

```bash
cd terraform
terraform apply -target=module.glue_catalog
```

#### 5. 파티션 복구

```bash
# 기존 파티션이 새 스키마를 인식하도록 복구
aws athena start-query-execution \
  --query-string "MSCK REPAIR TABLE rum_pipeline_db.rum_events" \
  --work-group rum-pipeline \
  --query-execution-context Database=rum_pipeline_db

# 쿼리 완료 대기
aws athena get-query-execution \
  --query-execution-id <execution-id> \
  --query 'QueryExecution.Status.State'
```

#### 6. Athena로 검증

```bash
# 새 스키마로 데이터 조회 확인
aws athena start-query-execution \
  --query-string "SELECT * FROM rum_pipeline_db.rum_events LIMIT 10" \
  --work-group rum-pipeline \
  --query-execution-context Database=rum_pipeline_db

# 새 컬럼이 NULL로 표시되면 하위 호환 정상
# 기존 컬럼 데이터가 정상 조회되는지 확인
```

### 롤백

```bash
# Terraform 코드를 이전 버전으로 되돌림
git checkout HEAD~1 -- terraform/modules/glue-catalog/main.tf
cd terraform && terraform apply -target=module.glue_catalog

# 파티션 재복구
aws athena start-query-execution \
  --query-string "MSCK REPAIR TABLE rum_pipeline_db.rum_events" \
  --work-group rum-pipeline \
  --query-execution-context Database=rum_pipeline_db
```

> **주의**: 컬럼 삭제/타입 변경은 기존 Parquet 파일과 호환되지 않을 수 있다.
> 반드시 컬럼 추가만 수행하고, 삭제가 필요하면 새 테이블을 생성하여 마이그레이션한다.

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: Glue Table Schema Migration

### Overview
Procedure for safely migrating Glue table schemas when the RUM event format changes.
Updates the schema while maintaining backwards compatibility with existing Parquet files.

### Prerequisites
- AWS CLI v2+ authenticated (`aws sts get-caller-identity`)
- Terraform >= 1.5 installed
- Athena query execution permissions
- Access to Glue database `rum_pipeline_db`

### Procedure

#### 1. Verify Current Schema

```bash
# Query current Glue table schema
aws glue get-table \
  --database-name rum_pipeline_db \
  --name rum_events \
  --query 'Table.StorageDescriptor.Columns' \
  --output table

# Check current partition keys
aws glue get-table \
  --database-name rum_pipeline_db \
  --name rum_events \
  --query 'Table.PartitionKeys' \
  --output table
```

#### 2. Modify Schema in Terraform

```bash
# Edit the glue-catalog module
# Modify the columns block in terraform/modules/glue-catalog/main.tf
# e.g., append new columns at the end of the columns list (maintains backwards compatibility)

cd terraform
terraform fmt -recursive
terraform validate
```

#### 3. Verify Changes

```bash
cd terraform
terraform plan -target=module.glue_catalog 2>&1 | tee /tmp/glue-plan.txt
# Confirm "~ update in-place" — STOP if you see "destroy"!
```

#### 4. Apply Schema Changes

```bash
cd terraform
terraform apply -target=module.glue_catalog
```

#### 5. Repair Partitions

```bash
# Repair partitions so they recognize the new schema
aws athena start-query-execution \
  --query-string "MSCK REPAIR TABLE rum_pipeline_db.rum_events" \
  --work-group rum-pipeline \
  --query-execution-context Database=rum_pipeline_db

# Wait for query completion
aws athena get-query-execution \
  --query-execution-id <execution-id> \
  --query 'QueryExecution.Status.State'
```

#### 6. Verify with Athena

```bash
# Verify data query with new schema
aws athena start-query-execution \
  --query-string "SELECT * FROM rum_pipeline_db.rum_events LIMIT 10" \
  --work-group rum-pipeline \
  --query-execution-context Database=rum_pipeline_db

# New columns showing NULL = backwards compatibility is working
# Verify existing column data is returned correctly
```

### Rollback

```bash
# Revert Terraform code to previous version
git checkout HEAD~1 -- terraform/modules/glue-catalog/main.tf
cd terraform && terraform apply -target=module.glue_catalog

# Re-repair partitions
aws athena start-query-execution \
  --query-string "MSCK REPAIR TABLE rum_pipeline_db.rum_events" \
  --work-group rum-pipeline \
  --query-execution-context Database=rum_pipeline_db
```

> **Warning**: Column deletion or type changes may be incompatible with existing Parquet files.
> Always perform column additions only. If deletion is needed, create a new table and migrate data.

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
