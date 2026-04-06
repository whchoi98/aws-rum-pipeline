<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Grafana Module

### Role
Amazon Managed Grafana 워크스페이스와 Athena 워크그룹을 관리하여 RUM 데이터 시각화 환경을 제공.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_grafana_workspace` | Managed Grafana 워크스페이스 (AWS SSO 인증, Athena 데이터 소스) |
| `aws_iam_role.grafana` | Grafana → Athena/S3/Glue 접근 IAM 역할 |
| `aws_iam_role_policy.grafana_athena` | Athena 쿼리 실행, S3 데이터 읽기/쓰기, Glue 카탈로그 접근 정책 |
| `aws_athena_workgroup` | Grafana 전용 Athena 워크그룹 (쿼리 결과 S3 저장, 100GB 스캔 제한) |

### Input Variables
| 변수 | 설명 |
|------|------|
| `project_name` | 리소스 이름 프리픽스 |
| `account_id` / `region` | Glue ARN 구성용 |
| `s3_bucket_arn` / `s3_bucket_name` | 데이터 읽기 + Athena 결과 저장 |
| `glue_database_name` | Glue 카탈로그 DB명 |

### Rules
- 인증은 AWS SSO만 지원 — SSO가 활성화되어 있어야 워크스페이스 생성 가능
- Athena 워크그룹에 `enforce_workgroup_configuration = true` 설정 — 사용자가 워크그룹 설정을 오버라이드할 수 없음
- 쿼리당 스캔 제한은 100GB (`bytes_scanned_cutoff_per_query`) — 비용 폭증 방지용
- Athena 결과는 `s3://{bucket}/athena-results/`에 저장
- `permission_type = SERVICE_MANAGED` — Grafana가 자체적으로 IAM 권한 관리

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Grafana Module

### Role
Manages the Amazon Managed Grafana workspace and Athena workgroup to provide a RUM data visualization environment.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_grafana_workspace` | Managed Grafana workspace (AWS SSO auth, Athena data source) |
| `aws_iam_role.grafana` | IAM role for Grafana to access Athena/S3/Glue |
| `aws_iam_role_policy.grafana_athena` | Athena query execution, S3 data read/write, Glue catalog access policy |
| `aws_athena_workgroup` | Grafana-dedicated Athena workgroup (query results in S3, 100GB scan limit) |

### Input Variables
| Variable | Description |
|----------|-------------|
| `project_name` | Resource name prefix |
| `account_id` / `region` | For Glue ARN construction |
| `s3_bucket_arn` / `s3_bucket_name` | Data reads + Athena result storage |
| `glue_database_name` | Glue catalog database name |

### Rules
- Authentication is AWS SSO only — SSO must be enabled before workspace creation
- Athena workgroup has `enforce_workgroup_configuration = true` — users cannot override workgroup settings
- Per-query scan limit is 100GB (`bytes_scanned_cutoff_per_query`) — prevents cost spikes
- Athena results are stored at `s3://{bucket}/athena-results/`
- `permission_type = SERVICE_MANAGED` — Grafana manages its own IAM permissions

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
