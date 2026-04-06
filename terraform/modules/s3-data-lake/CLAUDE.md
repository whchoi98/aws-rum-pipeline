<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## S3 Data Lake Module

### Role
RUM 이벤트 데이터를 저장하는 S3 버킷과 라이프사이클 정책을 관리.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_s3_bucket` | 데이터 레이크 메인 버킷 (`raw/`, `aggregated/`, `errors/` 프리픽스) |
| `aws_s3_bucket_versioning` | 버전 관리 활성화 |
| `aws_s3_bucket_server_side_encryption_configuration` | KMS 기반 서버 사이드 암호화 (Bucket Key 사용) |
| `aws_s3_bucket_public_access_block` | 퍼블릭 액세스 완전 차단 |
| `aws_s3_bucket_lifecycle_configuration` | raw 만료, aggregated 티어링(IA/Glacier), errors 만료 |

### Input Variables
| 변수 | 설명 | 기본값 |
|------|------|--------|
| `project_name` | 버킷 이름 프리픽스 | - |
| `account_id` | 글로벌 고유 버킷명 생성용 | - |
| `raw_expiration_days` | raw 데이터 만료일 | 90 |
| `error_expiration_days` | errors 데이터 만료일 | 30 |

### Rules
- 버킷 이름은 `{project_name}-data-lake-{account_id}` 형식으로 고정
- `aggregated/` 프리픽스 데이터는 90일 후 STANDARD_IA, 365일 후 GLACIER로 자동 전환
- KMS 암호화에 Bucket Key가 활성화되어 있으므로 KMS 호출 비용 절감
- 이 모듈은 의존성 체인의 최상위 — 대부분의 다른 모듈이 이 버킷 ARN/이름을 참조

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## S3 Data Lake Module

### Role
Manages the S3 bucket and lifecycle policies for storing RUM event data.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_s3_bucket` | Main data lake bucket (`raw/`, `aggregated/`, `errors/` prefixes) |
| `aws_s3_bucket_versioning` | Versioning enabled |
| `aws_s3_bucket_server_side_encryption_configuration` | KMS-based server-side encryption (Bucket Key enabled) |
| `aws_s3_bucket_public_access_block` | All public access blocked |
| `aws_s3_bucket_lifecycle_configuration` | raw expiration, aggregated tiering (IA/Glacier), errors expiration |

### Input Variables
| Variable | Description | Default |
|----------|-------------|---------|
| `project_name` | Bucket name prefix | - |
| `account_id` | For globally unique bucket naming | - |
| `raw_expiration_days` | Days before raw data expires | 90 |
| `error_expiration_days` | Days before error data expires | 30 |

### Rules
- Bucket name is fixed as `{project_name}-data-lake-{account_id}`
- `aggregated/` prefix data transitions to STANDARD_IA at 90 days, GLACIER at 365 days
- Bucket Key is enabled for KMS encryption, reducing KMS API call costs
- This module is at the top of the dependency chain — most other modules reference this bucket ARN/name

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
