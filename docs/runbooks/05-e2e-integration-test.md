<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: E2E 통합 테스트

### 개요
인제스트 파이프라인 전체 (API → Lambda → Firehose → S3) 를 검증하는 통합 테스트.

### 실행

```bash
# API Key 조회
API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text)

# API 엔드포인트 (Terraform output 또는 직접 지정)
API_URL="https://<api-id>.execute-api.ap-northeast-2.amazonaws.com"

# 테스트 실행
bash scripts/test-ingestion.sh "${API_URL}" "${API_KEY}"
```

### 테스트 항목

| # | 시나리오 | 기대 결과 |
|---|---------|----------|
| 1 | 인증 없이 요청 | 401 또는 403 |
| 2 | 잘못된 API Key | 403 |
| 3 | 유효한 이벤트 전송 | 200 |
| 4 | 잘못된 JSON 전송 | 400 |
| 5 | 복합 이벤트 (page_view + error + performance) | 200 |

### S3 데이터 도착 확인

```bash
# 2~3분 후 S3에 데이터 확인 (Firehose 버퍼링 시간)
TODAY=$(date +%Y/%m/%d)
aws s3 ls "s3://rum-pipeline-data-lake-<account-id>/raw/platform=web/year=$(date +%Y)/month=$(date +%m)/day=$(date +%d)/" \
  --recursive | tail -5
```

### Athena 쿼리 검증

```bash
aws athena start-query-execution \
  --query-string "SELECT count(*) FROM rum_pipeline_db.rum_events WHERE year='$(date +%Y)' AND month='$(date +%m)' AND day='$(date +%d)'" \
  --work-group rum-pipeline-athena \
  --region ap-northeast-2
```

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: E2E Integration Test

### Overview
Integration test to verify the entire ingest pipeline (API → Lambda → Firehose → S3).

### Execution

```bash
# Retrieve API Key
API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text)

# API endpoint (from Terraform output or specify directly)
API_URL="https://<api-id>.execute-api.ap-northeast-2.amazonaws.com"

# Run test
bash scripts/test-ingestion.sh "${API_URL}" "${API_KEY}"
```

### Test Cases

| # | Scenario | Expected Result |
|---|----------|-----------------|
| 1 | Request without authentication | 401 or 403 |
| 2 | Invalid API Key | 403 |
| 3 | Send valid event | 200 |
| 4 | Send invalid JSON | 400 |
| 5 | Composite events (page_view + error + performance) | 200 |

### Verify S3 Data Arrival

```bash
# Check S3 for data after 2-3 minutes (Firehose buffering time)
TODAY=$(date +%Y/%m/%d)
aws s3 ls "s3://rum-pipeline-data-lake-<account-id>/raw/platform=web/year=$(date +%Y)/month=$(date +%m)/day=$(date +%d)/" \
  --recursive | tail -5
```

### Athena Query Verification

```bash
aws athena start-query-execution \
  --query-string "SELECT count(*) FROM rum_pipeline_db.rum_events WHERE year='$(date +%Y)' AND month='$(date +%m)' AND day='$(date +%d)'" \
  --work-group rum-pipeline-athena \
  --region ap-northeast-2
```

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
