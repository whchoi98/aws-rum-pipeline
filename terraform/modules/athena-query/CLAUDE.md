<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Athena Query Module

### Role
Athena 쿼리 실행 및 결과 반환을 담당하는 Lambda 함수와 관련 IAM을 관리.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_lambda_function.athena_query` | Athena 쿼리 실행 및 결과 조회 Lambda |
| `aws_iam_role.athena_query` | Lambda IAM (Athena 실행, Glue 읽기, S3 읽기/쓰기) |
| `aws_cloudwatch_log_group` | Lambda 로그 (14일 보관) |

### Input Variables
| 변수 | 설명 |
|------|------|
| `project_name` | 리소스 이름 프리픽스 |
| `glue_database_name` | 쿼리 대상 Glue DB명 |
| `athena_workgroup` | Athena 워크그룹명 |
| `s3_bucket_arn` | Athena 결과 저장 및 데이터 읽기용 S3 |
| `lambda_source_dir` | Lambda 소스 경로 |

### Rules
- Athena/Glue IAM 권한이 `Resource = "*"` — 프로덕션에서는 특정 리소스로 제한 권장
- Lambda timeout은 60초 — 대규모 쿼리는 비동기 패턴 사용 검토
- 환경변수 `GLUE_DATABASE`, `ATHENA_WORKGROUP`을 Lambda에 전달
- 이 Lambda는 AgentCore 에이전트나 API에서 호출되어 RUM 데이터를 조회하는 용도

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Athena Query Module

### Role
Manages the Lambda function and IAM for executing Athena queries and returning results.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_lambda_function.athena_query` | Lambda for Athena query execution and result retrieval |
| `aws_iam_role.athena_query` | Lambda IAM (Athena execution, Glue read, S3 read/write) |
| `aws_cloudwatch_log_group` | Lambda logs (14-day retention) |

### Input Variables
| Variable | Description |
|----------|-------------|
| `project_name` | Resource name prefix |
| `glue_database_name` | Target Glue database name |
| `athena_workgroup` | Athena workgroup name |
| `s3_bucket_arn` | S3 for Athena results and data reads |
| `lambda_source_dir` | Lambda source path |

### Rules
- Athena/Glue IAM permissions use `Resource = "*"` — recommend scoping to specific resources in production
- Lambda timeout is 60s — consider async patterns for large queries
- Environment variables `GLUE_DATABASE`, `ATHENA_WORKGROUP` are passed to Lambda
- This Lambda is invoked by AgentCore agents or APIs to query RUM data

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
