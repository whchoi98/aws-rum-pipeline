<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: 비용 관리 및 최적화

### 개요
RUM Pipeline의 AWS 비용을 모니터링하고 최적화하는 절차.
주요 비용 동인, 월간 예상 비용, 최적화 전략, 알림 설정을 다룬다.

### 주요 비용 동인 (50K DAU 기준, 월 ~$124)

| 서비스 | 월 예상 비용 | 비고 |
|--------|-------------|------|
| S3 (저장/요청) | ~$5 | raw + processed 버킷 |
| Firehose | ~$15 | 수집량 기반 과금 |
| Lambda | ~$3 | 호출 횟수 + 실행 시간 |
| Athena | ~$25 | 쿼리당 스캔 데이터 과금 |
| Grafana | ~$9 | 뷰어 1명 기준 |
| EC2 (Agent UI) | ~$60 | t3.medium 기준 |
| 기타 (WAF, CloudWatch) | ~$7 | 요청 수 기반 |

### 절차

#### 1. 현재 비용 확인

```bash
# 이번 달 서비스별 비용 조회
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-04-30 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{"Tags":{"Key":"project","Values":["rum-pipeline"]}}' \
  --output table

# 일별 비용 추이 확인
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-04-06 \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --filter '{"Tags":{"Key":"project","Values":["rum-pipeline"]}}'
```

#### 2. Athena 쿼리 비용 최적화

```bash
# 워크그룹 스캔 제한 설정 (100GB)
aws athena update-work-group \
  --work-group rum-pipeline \
  --configuration-updates '{
    "BytesScannedCutoffPerQuery": 107374182400,
    "EnforceWorkGroupConfiguration": true
  }'

# 파티션 프루닝 활용 쿼리 예시 (비용 절감)
# BAD:  SELECT * FROM rum_events WHERE timestamp > '2026-04-01'
# GOOD: SELECT * FROM rum_events WHERE year='2026' AND month='04' AND day='01'

# Parquet 포맷 확인 (이미 적용됨 — 최대 90% 스캔 절감)
aws glue get-table \
  --database-name rum_pipeline_db \
  --name rum_events \
  --query 'Table.StorageDescriptor.InputFormat'
```

#### 3. S3 수명 주기 정책

```bash
# 현재 수명 주기 규칙 확인
aws s3api get-bucket-lifecycle-configuration \
  --bucket rum-pipeline-raw-data

# 수명 주기 규칙 설정 (예시)
aws s3api put-bucket-lifecycle-configuration \
  --bucket rum-pipeline-raw-data \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "raw-data-tiering",
        "Status": "Enabled",
        "Filter": {"Prefix": "year="},
        "Transitions": [
          {"Days": 30, "StorageClass": "STANDARD_IA"},
          {"Days": 90, "StorageClass": "GLACIER"}
        ],
        "Expiration": {"Days": 365}
      }
    ]
  }'
```

#### 4. Firehose 버퍼 튜닝

```bash
# 현재 버퍼 설정 확인
aws firehose describe-delivery-stream \
  --delivery-stream-name rum-pipeline-firehose \
  --query 'DeliveryStreamDescription.Destinations[0].S3DestinationDescription.BufferingHints'

# 버퍼 크기 증가 (더 큰 파일 = 더 적은 S3 PUT 요청 = 비용 절감)
# Terraform에서 buffer_size / buffer_interval 조정 권장
```

#### 5. 비용 태그 확인

```bash
# 프로젝트 태그가 모든 리소스에 적용되었는지 확인
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=project,Values=rum-pipeline \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output table
```

#### 6. 결제 알림 설정

```bash
# CloudWatch 결제 알림 (월 $150 초과 시)
aws cloudwatch put-metric-alarm \
  --alarm-name "rum-pipeline-billing-alarm" \
  --alarm-description "RUM Pipeline 월간 비용 $150 초과 알림" \
  --namespace "AWS/Billing" \
  --metric-name "EstimatedCharges" \
  --dimensions Name=Currency,Value=USD \
  --statistic Maximum \
  --period 86400 \
  --threshold 150 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "<sns-topic-arn>"
```

### 비용 절감 전략 요약
- **Athena**: 파티션 프루닝 필수, Parquet 포맷 유지, 워크그룹 스캔 제한
- **S3**: 30일 후 IA, 90일 후 Glacier, 365일 후 삭제
- **EC2**: Agent UI를 Fargate/Lambda로 전환 검토
- **Grafana**: 뷰어 수 최소화, SSO로 공유 계정 활용

### 롤백
비용 최적화 설정은 개별 AWS CLI 명령의 역순으로 원복한다.
S3 수명 주기 삭제: `aws s3api delete-bucket-lifecycle --bucket rum-pipeline-raw-data`

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: Cost Management and Optimization

### Overview
Procedures for monitoring and optimizing AWS costs for the RUM Pipeline.
Covers key cost drivers, monthly estimates, optimization strategies, and alert configuration.

### Key Cost Drivers (based on 50K DAU, ~$124/month)

| Service | Est. Monthly Cost | Notes |
|---------|------------------|-------|
| S3 (storage/requests) | ~$5 | raw + processed buckets |
| Firehose | ~$15 | Volume-based pricing |
| Lambda | ~$3 | Invocations + duration |
| Athena | ~$25 | Pay-per-query data scanned |
| Grafana | ~$9 | 1 viewer license |
| EC2 (Agent UI) | ~$60 | t3.medium baseline |
| Other (WAF, CloudWatch) | ~$7 | Request-based |

### Procedure

#### 1. Check Current Costs

```bash
# Query costs by service for current month
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-04-30 \
  --granularity MONTHLY \
  --metrics "UnblendedCost" \
  --group-by Type=DIMENSION,Key=SERVICE \
  --filter '{"Tags":{"Key":"project","Values":["rum-pipeline"]}}' \
  --output table

# Check daily cost trend
aws ce get-cost-and-usage \
  --time-period Start=2026-04-01,End=2026-04-06 \
  --granularity DAILY \
  --metrics "UnblendedCost" \
  --filter '{"Tags":{"Key":"project","Values":["rum-pipeline"]}}'
```

#### 2. Athena Query Cost Optimization

```bash
# Set workgroup scan limit (100GB)
aws athena update-work-group \
  --work-group rum-pipeline \
  --configuration-updates '{
    "BytesScannedCutoffPerQuery": 107374182400,
    "EnforceWorkGroupConfiguration": true
  }'

# Example: use partition pruning for cost savings
# BAD:  SELECT * FROM rum_events WHERE timestamp > '2026-04-01'
# GOOD: SELECT * FROM rum_events WHERE year='2026' AND month='04' AND day='01'

# Verify Parquet format (already applied — up to 90% scan reduction)
aws glue get-table \
  --database-name rum_pipeline_db \
  --name rum_events \
  --query 'Table.StorageDescriptor.InputFormat'
```

#### 3. S3 Lifecycle Policies

```bash
# Check current lifecycle rules
aws s3api get-bucket-lifecycle-configuration \
  --bucket rum-pipeline-raw-data

# Set lifecycle rules (example)
aws s3api put-bucket-lifecycle-configuration \
  --bucket rum-pipeline-raw-data \
  --lifecycle-configuration '{
    "Rules": [
      {
        "ID": "raw-data-tiering",
        "Status": "Enabled",
        "Filter": {"Prefix": "year="},
        "Transitions": [
          {"Days": 30, "StorageClass": "STANDARD_IA"},
          {"Days": 90, "StorageClass": "GLACIER"}
        ],
        "Expiration": {"Days": 365}
      }
    ]
  }'
```

#### 4. Firehose Buffer Tuning

```bash
# Check current buffer settings
aws firehose describe-delivery-stream \
  --delivery-stream-name rum-pipeline-firehose \
  --query 'DeliveryStreamDescription.Destinations[0].S3DestinationDescription.BufferingHints'

# Increase buffer size (larger files = fewer S3 PUT requests = cost savings)
# Recommended to adjust buffer_size / buffer_interval in Terraform
```

#### 5. Verify Cost Tags

```bash
# Verify project tag is applied to all resources
aws resourcegroupstaggingapi get-resources \
  --tag-filters Key=project,Values=rum-pipeline \
  --query 'ResourceTagMappingList[].ResourceARN' \
  --output table
```

#### 6. Set Up Billing Alerts

```bash
# CloudWatch billing alarm (triggers when monthly cost exceeds $150)
aws cloudwatch put-metric-alarm \
  --alarm-name "rum-pipeline-billing-alarm" \
  --alarm-description "RUM Pipeline monthly cost exceeds $150" \
  --namespace "AWS/Billing" \
  --metric-name "EstimatedCharges" \
  --dimensions Name=Currency,Value=USD \
  --statistic Maximum \
  --period 86400 \
  --threshold 150 \
  --comparison-operator GreaterThanThreshold \
  --evaluation-periods 1 \
  --alarm-actions "<sns-topic-arn>"
```

### Cost Reduction Strategy Summary
- **Athena**: Always use partition pruning, maintain Parquet format, enforce workgroup scan limits
- **S3**: Transition to IA after 30 days, Glacier after 90 days, expire after 365 days
- **EC2**: Consider migrating Agent UI to Fargate/Lambda
- **Grafana**: Minimize viewer count, use shared accounts via SSO

### Rollback
Reverse cost optimization settings by running AWS CLI commands in reverse order.
Delete S3 lifecycle: `aws s3api delete-bucket-lifecycle --bucket rum-pipeline-raw-data`

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
