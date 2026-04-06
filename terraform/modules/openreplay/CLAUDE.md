<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## OpenReplay Module

### Role
OpenReplay 셀프호스팅 세션 리플레이를 CF → ALB → EC2 아키텍처로 배포.
RDS PostgreSQL, ElastiCache Redis, S3를 외부 관리형 서비스로 사용.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_cloudfront_distribution` | HTTPS + SSO 인증 + /ingest 라우팅 |
| `aws_lb` | ALB — CF Prefix List SG |
| `aws_instance` | m7g.xlarge — Docker Compose (OpenReplay) |
| `aws_db_instance` | RDS PostgreSQL 16 |
| `aws_elasticache_cluster` | Redis 7.1 |
| `aws_s3_bucket` | 세션 녹화 데이터 |

### Rules
- `enable_openreplay = true` + `private_subnet_ids` 필수
- EC2 user_data로 Docker Compose 자동 설치
- 시크릿은 SSM Parameter Store에서 읽음 (하드코딩 금지)
- /ingest/* 경로는 인증 없음 (트래커 데이터 수집)
- /* 경로는 Lambda@Edge SSO 인증

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## OpenReplay Module

### Role
Deploys self-hosted OpenReplay session replay via CF → ALB → EC2 architecture.
Uses RDS PostgreSQL, ElastiCache Redis, and S3 as external managed services.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_cloudfront_distribution` | HTTPS + SSO auth + /ingest routing |
| `aws_lb` | ALB — CF Prefix List SG |
| `aws_instance` | m7g.xlarge — Docker Compose (OpenReplay) |
| `aws_db_instance` | RDS PostgreSQL 16 |
| `aws_elasticache_cluster` | Redis 7.1 |
| `aws_s3_bucket` | Session recording data |

### Rules
- `enable_openreplay = true` + `private_subnet_ids` required
- EC2 user_data auto-installs Docker Compose
- Secrets read from SSM Parameter Store (no hardcoding)
- /ingest/* path has no authentication (tracker data collection)
- /* path uses Lambda@Edge SSO authentication

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
