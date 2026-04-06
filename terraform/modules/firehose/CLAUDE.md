<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Firehose Module

### Role
Kinesis Data Firehose 전송 스트림과 Transform Lambda를 관리하여 JSON 이벤트를 Parquet로 변환 후 S3에 동적 파티셔닝으로 저장.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_kinesis_firehose_delivery_stream` | S3로 이벤트 전송 (동적 파티셔닝 + Parquet 변환) |
| `aws_lambda_function.transform` | Firehose 처리기 — JSON 정규화 및 파티션 키 추출 |
| `aws_iam_role.firehose` | Firehose용 IAM (S3, Lambda, Glue, CloudWatch 권한) |
| `aws_iam_role.transform_lambda` | Transform Lambda용 IAM |
| `aws_cloudwatch_log_group` (x2) | Firehose 전송 로그 + Transform Lambda 로그 |

### Input Variables
| 변수 | 설명 | 기본값 |
|------|------|--------|
| `s3_bucket_arn` | 대상 S3 버킷 ARN | - |
| `glue_database_name` / `glue_table_name` | Parquet 스키마 참조용 Glue 테이블 | - |
| `lambda_source_dir` | Transform Lambda 소스 경로 | - |
| `buffering_size_mb` | 버퍼 크기 (동적 파티셔닝 시 최소 64MB) | 64 |
| `buffering_interval_sec` | 버퍼 간격 | 60 |

### Rules
- 동적 파티셔닝이 활성화되어 있으므로 `buffering_size_mb`는 최소 64MB 이상이어야 함
- S3 프리픽스에 `!{partitionKeyFromLambda:*}` 플레이스홀더 사용 — Transform Lambda가 반환하는 파티션 키와 일치해야 함
- 에러 출력은 `errors/` 프리픽스로 별도 저장
- Parquet 변환은 Glue 테이블 스키마를 직접 참조하므로, 스키마 변경 시 glue-catalog 모듈과 동기화 필수
- Transform Lambda timeout은 60초이며 Firehose Lambda 처리기 제한(5분)보다 짧아야 함

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Firehose Module

### Role
Manages the Kinesis Data Firehose delivery stream and Transform Lambda to convert JSON events to Parquet and store them in S3 with dynamic partitioning.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_kinesis_firehose_delivery_stream` | Delivers events to S3 (dynamic partitioning + Parquet conversion) |
| `aws_lambda_function.transform` | Firehose processor — JSON normalization and partition key extraction |
| `aws_iam_role.firehose` | IAM for Firehose (S3, Lambda, Glue, CloudWatch permissions) |
| `aws_iam_role.transform_lambda` | IAM for Transform Lambda |
| `aws_cloudwatch_log_group` (x2) | Firehose delivery logs + Transform Lambda logs |

### Input Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `s3_bucket_arn` | Target S3 bucket ARN | - |
| `glue_database_name` / `glue_table_name` | Glue table for Parquet schema reference | - |
| `lambda_source_dir` | Transform Lambda source path | - |
| `buffering_size_mb` | Buffer size (min 64MB with dynamic partitioning) | 64 |
| `buffering_interval_sec` | Buffer interval | 60 |

### Rules
- Dynamic partitioning is enabled, so `buffering_size_mb` must be at least 64MB
- S3 prefix uses `!{partitionKeyFromLambda:*}` placeholders — must match partition keys returned by Transform Lambda
- Error output is stored separately under `errors/` prefix
- Parquet conversion directly references the Glue table schema, so schema changes must be synced with glue-catalog module
- Transform Lambda timeout is 60s and must be shorter than the Firehose Lambda processor limit (5 min)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
