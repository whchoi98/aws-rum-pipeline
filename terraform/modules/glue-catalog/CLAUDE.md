<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Glue Catalog Module

### Role
RUM 데이터에 대한 Glue 데이터베이스와 3개 외부 테이블 스키마를 관리하여 Athena 쿼리를 가능하게 함.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_glue_catalog_database` | RUM 파이프라인 데이터 카탈로그 DB (`{project}_db`) |
| `aws_glue_catalog_table.rum_events` | 원시 이벤트 테이블 (Parquet, `raw/` 경로, 5개 파티션 키) |
| `aws_glue_catalog_table.rum_hourly_metrics` | 시간별 집계 메트릭 테이블 (Parquet, `aggregated/hourly/`) |
| `aws_glue_catalog_table.rum_daily_summary` | 일별 요약 테이블 (Parquet, `aggregated/daily/`) |

### Input Variables
| 변수 | 설명 |
|------|------|
| `project_name` | DB 이름 생성용 (하이픈은 언더스코어로 자동 치환) |
| `s3_bucket_name` | 테이블 location이 가리킬 S3 버킷명 |

### Rules
- DB 이름에서 하이픈(`-`)은 언더스코어(`_`)로 자동 치환됨 (`replace()`)
- `rum_events` 테이블 파티션 키: `platform`, `year`, `month`, `day`, `hour` — Firehose 동적 파티셔닝과 일치해야 함
- 모든 테이블은 `EXTERNAL_TABLE` 타입이며 Parquet + SNAPPY 압축 사용
- 스키마 변경 시 Firehose의 `data_format_conversion_configuration`과 반드시 동기화 필요

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Glue Catalog Module

### Role
Manages the Glue database and 3 external table schemas for RUM data, enabling Athena queries.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_glue_catalog_database` | RUM pipeline data catalog DB (`{project}_db`) |
| `aws_glue_catalog_table.rum_events` | Raw events table (Parquet, `raw/` path, 5 partition keys) |
| `aws_glue_catalog_table.rum_hourly_metrics` | Hourly aggregated metrics table (Parquet, `aggregated/hourly/`) |
| `aws_glue_catalog_table.rum_daily_summary` | Daily summary table (Parquet, `aggregated/daily/`) |

### Input Variables
| Variable | Description |
|----------|-------------|
| `project_name` | For DB naming (hyphens auto-replaced with underscores) |
| `s3_bucket_name` | S3 bucket name for table locations |

### Rules
- Hyphens (`-`) in DB name are auto-replaced with underscores (`_`) via `replace()`
- `rum_events` table partition keys: `platform`, `year`, `month`, `day`, `hour` — must match Firehose dynamic partitioning
- All tables are `EXTERNAL_TABLE` type using Parquet + SNAPPY compression
- Schema changes must be synchronized with Firehose's `data_format_conversion_configuration`

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
