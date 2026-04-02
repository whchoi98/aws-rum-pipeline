# Phase 1c — Amazon Managed Grafana + Athena Dashboard Design

**Date:** 2026-04-02
**Status:** Approved
**Depends on:** Phase 1a (infrastructure), Phase 1b (SDK + simulator for data)

## 1. Overview

Amazon Managed Grafana 워크스페이스를 배포하고 Athena 데이터 소스를 연결하여 RUM 파이프라인 데이터를 시각화하는 대시보드를 구축한다.

### Goals

- Amazon Managed Grafana 워크스페이스 Terraform 배포
- Athena 데이터 소스 연동 (rum_pipeline_db)
- 3개 대시보드: Core Web Vitals, Error Monitoring, Traffic Overview
- IAM 기반 인증 (초기), 향후 SSO 확장 가능

### Non-Goals

- Grafana 알림 (SNS/Slack 연동은 Phase 1e)
- 집계 테이블 (rum_hourly_metrics, rum_daily_summary는 Phase 1e)
- 셀프서비스 대시보드 커스터마이징

## 2. Architecture

```
Amazon Managed Grafana
  ├── Workspace: rum-pipeline-grafana
  ├── IAM Role: rum-pipeline-grafana-role
  │   ├── athena:StartQueryExecution
  │   ├── athena:GetQueryResults
  │   ├── s3:GetObject (data lake bucket)
  │   ├── s3:PutObject (athena query results bucket)
  │   ├── s3:GetBucketLocation
  │   └── glue:GetTable, GetDatabase
  ├── Data Source: Amazon Athena
  │   ├── Database: rum_pipeline_db
  │   ├── Workgroup: rum-pipeline-athena
  │   └── Output Location: s3://rum-pipeline-data-lake-{account}/athena-results/
  └── Dashboards (3)
```

## 3. Terraform Module

```
terraform/modules/grafana/
├── main.tf         ← Grafana workspace + IAM + Athena workgroup
├── variables.tf
├── outputs.tf
└── dashboards/
    ├── web-vitals.json
    ├── error-monitoring.json
    └── traffic-overview.json
```

### 3.1 Resources

| Resource | 설명 |
|----------|------|
| aws_grafana_workspace | Managed Grafana 워크스페이스 (CURRENT_ACCOUNT auth) |
| aws_iam_role | Grafana → Athena/S3/Glue 접근 IAM Role |
| aws_athena_workgroup | rum-pipeline-athena (쿼리 결과 S3 위치) |
| aws_s3_object (athena-results/) | Athena 쿼리 결과 저장 폴더 (data lake 버킷 내) |

### 3.2 Variables

```hcl
variable "project_name" { type = string }
variable "account_id" { type = string }
variable "region" { type = string }
variable "s3_bucket_arn" { type = string }
variable "s3_bucket_name" { type = string }
variable "glue_database_name" { type = string }
variable "tags" { type = map(string), default = {} }
```

### 3.3 Outputs

```hcl
output "workspace_endpoint" { value = grafana workspace URL }
output "workspace_id" { value = grafana workspace ID }
output "athena_workgroup" { value = athena workgroup name }
```

## 4. Dashboard Definitions

### 4.1 Core Web Vitals Dashboard

| 패널 | 타입 | Athena 쿼리 |
|------|------|-------------|
| LCP Overview | Gauge | `SELECT approx_percentile(CAST(payload.value AS DOUBLE), 0.75) FROM rum_events WHERE event_name='lcp' AND year='{year}' AND month='{month}' AND day='{day}'` |
| LCP Trend (24h) | Time series | `SELECT date_trunc('hour', from_unixtime(timestamp/1000)) as hr, approx_percentile(CAST(payload.value AS DOUBLE), 0.75) FROM rum_events WHERE event_name='lcp' AND ...` |
| CLS Overview | Gauge | Similar query for cls |
| INP Overview | Gauge | Similar query for inp |
| CWV by Page | Table | Group by context.url, show p75 for each metric |
| Rating Distribution | Pie chart | Count by payload.rating (good/needs-improvement/poor) |

### 4.2 Error Monitoring Dashboard

| 패널 | 타입 | Athena 쿼리 |
|------|------|-------------|
| Error Rate | Stat + Sparkline | `SELECT COUNT(*) FILTER (WHERE event_type='error') * 100.0 / COUNT(*) FROM rum_events WHERE ...` |
| Error Trend (24h) | Time series | Hourly error count |
| Top 10 Errors | Table | Group by payload.message, count desc |
| Error by Type | Pie chart | js_error vs unhandled_rejection |
| Recent Errors | Table | Latest 20 errors with stack, url, timestamp |

### 4.3 Traffic Overview Dashboard

| 패널 | 타입 | Athena 쿼리 |
|------|------|-------------|
| Total Events | Stat | `SELECT COUNT(*) FROM rum_events WHERE ...` |
| Events by Type | Pie chart | Group by event_type |
| Events Trend (24h) | Time series | Hourly event count |
| Top Pages | Table | Group by context.url, count desc |
| Platform Distribution | Pie chart | Group by platform |
| Browser Distribution | Bar chart | Group by context.device.browser |

## 5. Athena Workgroup

- **Name:** rum-pipeline-athena
- **Output:** s3://rum-pipeline-data-lake-{account}/athena-results/
- **Query limit:** 100MB scan per query (비용 제어)
- **Auto-cleanup:** 7일 후 결과 삭제 (S3 lifecycle)

## 6. IAM Permissions

Grafana workspace IAM role:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "athena:GetDatabase",
        "athena:GetDataCatalog",
        "athena:GetTableMetadata",
        "athena:ListDatabases",
        "athena:ListDataCatalogs",
        "athena:ListTableMetadata",
        "athena:StartQueryExecution",
        "athena:StopQueryExecution",
        "athena:GetQueryExecution",
        "athena:GetQueryResults",
        "athena:GetWorkGroup",
        "athena:ListWorkGroups"
      ],
      "Resource": "*"
    },
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket",
        "s3:GetBucketLocation",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::{bucket}",
        "arn:aws:s3:::{bucket}/*"
      ]
    },
    {
      "Effect": "Allow",
      "Action": [
        "glue:GetTable",
        "glue:GetTables",
        "glue:GetDatabase",
        "glue:GetDatabases",
        "glue:GetPartitions"
      ],
      "Resource": [
        "arn:aws:glue:{region}:{account}:catalog",
        "arn:aws:glue:{region}:{account}:database/rum_pipeline_db",
        "arn:aws:glue:{region}:{account}:table/rum_pipeline_db/*"
      ]
    }
  ]
}
```

## 7. Authentication

- **Phase 1c:** `CURRENT_ACCOUNT` 인증 (AWS IAM Console 로그인)
- **향후:** AWS IAM Identity Center (SSO) 연동으로 팀원 접근 제어
- Grafana admin은 Terraform에서 IAM user/role로 지정

## 8. Cost Estimate

| 항목 | 월 비용 |
|------|---------|
| Managed Grafana (1 editor) | $9.00 |
| Athena 쿼리 (~10GB 스캔/월) | ~$0.50 |
| S3 (쿼리 결과) | <$0.10 |
| **합계** | **~$10/월** |

## 9. Testing

- Terraform validate + plan → 리소스 확인
- Grafana 워크스페이스 접속 → Athena 데이터 소스 연결 확인
- 각 대시보드 패널 → 데이터 표시 확인 (시뮬레이터 데이터 필요)

## 10. Implementation Order

1. Terraform 모듈 (Grafana workspace + IAM + Athena workgroup)
2. Dashboard JSON 파일 생성
3. Root main.tf 연결 + 배포
4. 대시보드 프로비저닝 (API 또는 수동 import)
5. 시뮬레이터 데이터로 검증
