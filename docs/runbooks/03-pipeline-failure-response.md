<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: 인제스트 파이프라인 장애 대응

### 개요
API Gateway → Lambda → Firehose → S3 파이프라인에서 장애 발생 시 진단 및 복구.

### 증상별 진단

#### 1. API Gateway 5xx 증가

```bash
# Ingest Lambda 에러 로그 확인
aws logs filter-log-events \
  --log-group-name /aws/lambda/rum-pipeline-ingest \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR" \
  --query 'events[].message' --output text

# Lambda 스로틀 확인
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Throttles \
  --dimensions Name=FunctionName,Value=rum-pipeline-ingest \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Sum
```

#### 2. Firehose 전송 실패

```bash
# Firehose 에러 로그
aws logs filter-log-events \
  --log-group-name /aws/firehose/rum-pipeline-events \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR"

# S3 errors/ 접두사 확인 (실패한 레코드 저장됨)
aws s3 ls s3://rum-pipeline-data-lake-<account-id>/errors/ --recursive | tail -20
```

#### 3. Transform Lambda 실패

```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/rum-pipeline-transform \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR"
```

#### 4. 파티션 누락 (Athena에서 데이터 안 보임)

```bash
# 파티션 복구 Lambda 수동 실행
aws lambda invoke \
  --function-name rum-pipeline-partition-repair \
  --payload '{}' /dev/stdout
```

### 복구

| 장애 | 복구 방법 |
|------|----------|
| Lambda 스로틀 | Reserved Concurrency 증가 |
| Firehose 버퍼 오버플로우 | 버퍼 크기 증가 (Terraform `buffering_size_mb`) |
| S3 권한 에러 | IAM 역할 정책 확인 |
| Transform 스키마 에러 | `errors/` 디렉터리에서 실패 레코드 분석 |
| 파티션 누락 | `MSCK REPAIR TABLE rum_pipeline_db.rum_events` 실행 |

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: Ingest Pipeline Failure Response

### Overview
Diagnosis and recovery when failures occur in the API Gateway → Lambda → Firehose → S3 pipeline.

### Diagnosis by Symptom

#### 1. API Gateway 5xx Increase

```bash
# Check Ingest Lambda error logs
aws logs filter-log-events \
  --log-group-name /aws/lambda/rum-pipeline-ingest \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR" \
  --query 'events[].message' --output text

# Check Lambda throttles
aws cloudwatch get-metric-statistics \
  --namespace AWS/Lambda \
  --metric-name Throttles \
  --dimensions Name=FunctionName,Value=rum-pipeline-ingest \
  --start-time $(date -u -d '1 hour ago' +%Y-%m-%dT%H:%M:%S) \
  --end-time $(date -u +%Y-%m-%dT%H:%M:%S) \
  --period 300 --statistics Sum
```

#### 2. Firehose Delivery Failure

```bash
# Firehose error logs
aws logs filter-log-events \
  --log-group-name /aws/firehose/rum-pipeline-events \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR"

# Check S3 errors/ prefix (failed records are stored here)
aws s3 ls s3://rum-pipeline-data-lake-<account-id>/errors/ --recursive | tail -20
```

#### 3. Transform Lambda Failure

```bash
aws logs filter-log-events \
  --log-group-name /aws/lambda/rum-pipeline-transform \
  --start-time $(date -d '1 hour ago' +%s000) \
  --filter-pattern "ERROR"
```

#### 4. Missing Partitions (Data Not Visible in Athena)

```bash
# Manually invoke partition repair Lambda
aws lambda invoke \
  --function-name rum-pipeline-partition-repair \
  --payload '{}' /dev/stdout
```

### Recovery

| Failure | Recovery Method |
|---------|----------------|
| Lambda throttle | Increase Reserved Concurrency |
| Firehose buffer overflow | Increase buffer size (Terraform `buffering_size_mb`) |
| S3 permission error | Verify IAM role policy |
| Transform schema error | Analyze failed records in `errors/` directory |
| Missing partitions | Run `MSCK REPAIR TABLE rum_pipeline_db.rum_events` |

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
