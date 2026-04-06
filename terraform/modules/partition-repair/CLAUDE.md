<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Partition Repair Module

### Role
EventBridge 스케줄로 Lambda를 주기적으로 실행하여 Glue 테이블의 파티션을 자동 복구 (MSCK REPAIR TABLE).

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_lambda_function.partition_repair` | Athena를 통해 MSCK REPAIR TABLE 실행 |
| `aws_cloudwatch_event_rule` | EventBridge 스케줄 (기본 15분마다) |
| `aws_cloudwatch_event_target` | EventBridge → Lambda 연결 |
| `aws_lambda_permission` | EventBridge가 Lambda를 호출할 수 있는 권한 |
| `aws_iam_role.partition_repair` | Lambda IAM (Athena, Glue, S3, CloudWatch Logs) |

### Input Variables
| 변수 | 설명 | 기본값 |
|------|------|--------|
| `glue_database_name` / `glue_table_name` | 복구할 Glue 테이블 | - |
| `athena_workgroup` | Athena 워크그룹명 | - |
| `s3_bucket_arn` | Athena 결과 저장용 S3 | - |
| `lambda_source_dir` | Lambda 소스 경로 | - |
| `schedule` | EventBridge 스케줄 표현식 | `rate(15 minutes)` |

### Rules
- Lambda timeout은 120초 — MSCK REPAIR TABLE은 파티션이 많을수록 오래 걸리므로 충분한 여유 필요
- Glue/Athena IAM 권한이 `Resource = "*"` — 보안 강화 시 특정 리소스로 제한 가능
- 환경변수 `GLUE_DATABASE`, `GLUE_TABLE`, `ATHENA_WORKGROUP`을 Lambda에 전달
- Firehose가 동적 파티셔닝으로 새 파티션을 생성해도 Glue에 자동 등록되지 않으므로 이 모듈이 필수

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Partition Repair Module

### Role
Periodically runs a Lambda via EventBridge schedule to auto-repair Glue table partitions (MSCK REPAIR TABLE).

### Key Resources
| Resource | Role |
|----------|------|
| `aws_lambda_function.partition_repair` | Executes MSCK REPAIR TABLE via Athena |
| `aws_cloudwatch_event_rule` | EventBridge schedule (default every 15 minutes) |
| `aws_cloudwatch_event_target` | EventBridge to Lambda wiring |
| `aws_lambda_permission` | Permission for EventBridge to invoke Lambda |
| `aws_iam_role.partition_repair` | Lambda IAM (Athena, Glue, S3, CloudWatch Logs) |

### Input Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `glue_database_name` / `glue_table_name` | Glue table to repair | - |
| `athena_workgroup` | Athena workgroup name | - |
| `s3_bucket_arn` | S3 for Athena query results | - |
| `lambda_source_dir` | Lambda source path | - |
| `schedule` | EventBridge schedule expression | `rate(15 minutes)` |

### Rules
- Lambda timeout is 120s — MSCK REPAIR TABLE takes longer with more partitions, so sufficient headroom is needed
- Glue/Athena IAM permissions use `Resource = "*"` — can be scoped to specific resources for tighter security
- Environment variables `GLUE_DATABASE`, `GLUE_TABLE`, `ATHENA_WORKGROUP` are passed to Lambda
- This module is essential because Firehose dynamic partitioning creates new S3 partitions that are not auto-registered in Glue

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
