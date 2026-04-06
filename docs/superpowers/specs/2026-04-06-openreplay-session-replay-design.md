# OpenReplay Session Replay Integration — Design Spec

**Date**: 2026-04-06
**Status**: Approved
**Author**: Claude Code + WooHyung Choi

---

## 1. Overview

OpenReplay 셀프호스팅을 AWS RUM Pipeline에 추가하여 세션 리플레이 기능을 제공한다.
기존 RUM SDK(이벤트 수집 파이프라인)는 변경 없이 유지하고, OpenReplay 트래커를 병행 운영한다.

### Goals

- 사용자 세션을 녹화하고 재생할 수 있는 OpenReplay 대시보드 제공
- 기존 CF → CF Prefix List SG → ALB → EC2 패턴으로 배포
- 기존 Cognito SSO 인증을 재사용하여 대시보드 접근 제어
- 핵심 스토리지를 AWS 관리형 서비스(RDS, ElastiCache, S3)로 분리

### Non-Goals

- 기존 RUM SDK 수정 또는 OpenReplay 트래커와의 세션 ID 연동
- OpenReplay Kubernetes/Helm 배포
- OpenReplay SaaS (클라우드) 사용

---

## 2. Architecture

### 2.1 System Diagram

```
┌─────────────────────────────────────────────────────────────────────┐
│                         사용자 브라우저                                │
│                                                                     │
│  ┌────────────────┐               ┌──────────────────────────┐      │
│  │ 기존 RUM SDK   │               │ OpenReplay Tracker JS    │      │
│  │ (TypeScript)   │               │ (별도 스크립트)            │      │
│  └───────┬────────┘               └──────────┬───────────────┘      │
└──────────┼───────────────────────────────────┼──────────────────────┘
           │                                   │
           ▼                                   ▼
┌──────────────────────┐         ┌────────────────────────────────────┐
│ 기존 RUM Pipeline    │         │         OpenReplay Stack           │
│                      │         │                                    │
│ API GW → Lambda      │         │  CloudFront (SSO: Lambda@Edge)    │
│  → Firehose → S3     │         │         │                         │
│  → Athena/Grafana    │         │         ▼                         │
│                      │         │  ALB (CF Prefix List SG)          │
│  (변경 없음)          │         │    ├── /* → EC2:80 (Dashboard)    │
│                      │         │    └── /ingest/* → EC2:9443       │
└──────────────────────┘         │         │                         │
                                 │         ▼                         │
                                 │  EC2 m7g.xlarge (Docker Compose)  │
                                 │  ├── Frontend (Nginx :80)         │
                                 │  ├── Backend/API (Chalice :9443)  │
                                 │  ├── Kafka + Zookeeper            │
                                 │  ├── Sink Workers                 │
                                 │  ├── Alerts                       │
                                 │  └── Integrations                 │
                                 │         │       │       │         │
                                 │         ▼       ▼       ▼         │
                                 │  ┌──────┐ ┌─────┐ ┌──────────┐   │
                                 │  │ RDS  │ │ S3  │ │ElastiCa- │   │
                                 │  │PG 16 │ │녹화 │ │che Redis │   │
                                 │  └──────┘ └─────┘ └──────────┘   │
                                 └────────────────────────────────────┘
```

### 2.2 Network & Security

| 리소스 | 인바운드 | 아웃바운드 |
|--------|----------|-----------|
| CloudFront | 인터넷 (HTTPS) | ALB (HTTP:80) |
| ALB SG | CF Managed Prefix List → 80 | EC2 SG |
| EC2 SG | ALB SG → 80, ALB SG → 9443 | 0.0.0.0/0 |
| RDS SG | EC2 SG → 5432 | — |
| ElastiCache SG | EC2 SG → 6379 | — |
| S3 | EC2 IAM Role | — |

### 2.3 CloudFront Behavior Routing

| 우선순위 | 경로 패턴 | Origin | 인증 | 캐시 |
|----------|-----------|--------|------|------|
| 1 | `/ingest/*` | ALB → EC2:9443 | 없음 (트래커 데이터) | TTL 0 |
| 2 | `/*` (기본) | ALB → EC2:80 | Lambda@Edge SSO | TTL 0 |

`/ingest/*`는 인증 없음 — 익명 사용자의 트래커 데이터 수집 경로.
`/*`는 SSO 보호 — 관리자 대시보드.

---

## 3. Infrastructure Components

### 3.1 Terraform Module

```
terraform/modules/openreplay/
  ├── main.tf          # CF, ALB, SG, EC2, user_data
  ├── rds.tf           # RDS PostgreSQL
  ├── elasticache.tf   # ElastiCache Redis
  ├── s3.tf            # 세션 녹화 S3 버킷
  ├── variables.tf
  └── outputs.tf
```

CDK 대응: `cdk/lib/constructs/openreplay.ts`

### 3.2 Input Variables

| 변수 | 타입 | 기본값 | 설명 |
|------|------|--------|------|
| `project_name` | string | — | 리소스 이름 접두사 |
| `environment` | string | — | dev/prod |
| `vpc_id` | string | — | VPC ID |
| `public_subnet_ids` | list(string) | — | ALB + EC2 서브넷 |
| `private_subnet_ids` | list(string) | — | RDS + ElastiCache 서브넷 |
| `instance_type` | string | `m7g.xlarge` | EC2 인스턴스 타입 |
| `db_instance_class` | string | `db.t4g.medium` | RDS 인스턴스 클래스 |
| `edge_auth_qualified_arn` | string | `""` | Lambda@Edge SSO ARN |
| `tags` | map(string) | `{}` | 공통 태그 |

### 3.3 Outputs

| 출력 | 설명 |
|------|------|
| `cloudfront_domain` | OpenReplay 대시보드 URL |
| `ingest_endpoint` | 트래커 ingest URL (`https://<cf>/ingest`) |
| `rds_endpoint` | RDS 엔드포인트 |
| `s3_bucket_name` | 세션 녹화 S3 버킷명 |

---

## 4. EC2 Docker Compose Configuration

### 4.1 user_data Bootstrap Flow

```
1. Docker Engine + Docker Compose v2 설치
2. OpenReplay self-hosting 스크립트 clone/실행
3. SSM Parameter Store에서 시크릿 읽기:
   - /rum-pipeline/{env}/openreplay/db-password
   - /rum-pipeline/{env}/openreplay/jwt-secret
4. docker-compose.override.yml 생성 (외부 서비스 연결)
5. 내부 PostgreSQL/Redis/MinIO 컨테이너 비활성화
6. docker compose up -d
```

### 4.2 docker-compose.override.yml

내부 DB/Cache/Storage 서비스를 비활성화하고 AWS 관리형으로 연결:

```yaml
services:
  postgresql:
    profiles: ["disabled"]
  redis:
    profiles: ["disabled"]
  minio:
    profiles: ["disabled"]

  chalice:
    environment:
      pg_host: "${RDS_ENDPOINT}"
      pg_port: "5432"
      pg_dbname: "openreplay"
      pg_user: "openreplay"
      pg_password: "${DB_PASSWORD}"
      REDIS_HOST: "${ELASTICACHE_ENDPOINT}"
      S3_BUCKET_NAME: "${S3_BUCKET}"
      AWS_DEFAULT_REGION: "ap-northeast-2"

  backend:
    environment:
      pg_host: "${RDS_ENDPOINT}"
      pg_port: "5432"
      pg_dbname: "openreplay"
      pg_user: "openreplay"
      pg_password: "${DB_PASSWORD}"
      REDIS_HOST: "${ELASTICACHE_ENDPOINT}"
      S3_BUCKET_NAME: "${S3_BUCKET}"
      AWS_DEFAULT_REGION: "ap-northeast-2"

  sink:
    environment:
      pg_host: "${RDS_ENDPOINT}"
      REDIS_HOST: "${ELASTICACHE_ENDPOINT}"
      S3_BUCKET_NAME: "${S3_BUCKET}"
```

### 4.3 EC2 컨테이너 목록 (관리형 분리 후)

| 컨테이너 | 역할 | 포트 |
|-----------|------|------|
| frontend | 대시보드 UI (Nginx) | 80 |
| chalice | REST API + Ingest | 9443 |
| sink | Kafka → RDS/S3 기록 | 내부 |
| kafka | 이벤트 스트리밍 | 9092 (내부) |
| zookeeper | Kafka 메타데이터 | 2181 (내부) |
| alerts | 알림 처리 | 내부 |
| integrations | 외부 연동 | 내부 |

### 4.4 Secrets Management

```
SSM Parameter Store:
  /rum-pipeline/{env}/openreplay/db-password    # RDS 비밀번호 (SecureString)
  /rum-pipeline/{env}/openreplay/jwt-secret     # JWT 시크릿 (SecureString)
```

EC2 IAM Role에 SSM 읽기 권한 포함. user_data에서 `aws ssm get-parameter`로 주입.

---

## 5. AWS Managed Services Specs

### 5.1 RDS PostgreSQL

| 항목 | 값 |
|------|-----|
| 엔진 | PostgreSQL 16 |
| 인스턴스 | db.t4g.medium (2 vCPU, 4GB) |
| 스토리지 | gp3 20GB, 자동 확장 100GB |
| Multi-AZ | dev: 비활성, prod: 활성 |
| 백업 | 7일 자동 백업 |
| DB 이름 | `openreplay` |
| 사용자 | `openreplay` |
| 서브넷 | 프라이빗 (`private_subnet_ids`) |
| 암호화 | KMS 기본 키 |

### 5.2 ElastiCache Redis

| 항목 | 값 |
|------|-----|
| 엔진 | Redis 7.x |
| 노드 | cache.t4g.micro (2 vCPU, 0.5GB) |
| 클러스터 모드 | 비활성 (단일 노드) |
| 서브넷 | 프라이빗 (`private_subnet_ids`) |

### 5.3 S3 세션 녹화 버킷

| 항목 | 값 |
|------|-----|
| 버킷명 | `{project_name}-openreplay-recordings-{account_id}` |
| 버전 관리 | 비활성 |
| 라이프사이클 | 30일 → IA, 90일 → Glacier, 365일 → 삭제 |
| 암호화 | SSE-S3 |
| 접근 | EC2 IAM Role |

---

## 6. Tracker Integration

기존 RUM SDK와 OpenReplay 트래커를 병행 운영. 두 SDK는 독립적.

```html
<!-- 기존 RUM SDK (변경 없음) -->
<script src="https://<rum-api>/rum-sdk.js"></script>
<script>
  RumSDK.init({ endpoint: 'https://<rum-api>', apiKey: '...' });
</script>

<!-- OpenReplay 트래커 (추가) -->
<script src="https://<openreplay-cf>/ingest/openreplay.js"></script>
<script>
  const tracker = new OpenReplay({
    projectKey: '<openreplay-project-key>',
    ingestPoint: 'https://<openreplay-cf>/ingest',
  });
  tracker.start();
</script>
```

---

## 7. Project Changes

### New Files

| 경로 | 역할 |
|------|------|
| `terraform/modules/openreplay/main.tf` | CF, ALB, SG, EC2, user_data |
| `terraform/modules/openreplay/rds.tf` | RDS PostgreSQL |
| `terraform/modules/openreplay/elasticache.tf` | ElastiCache Redis |
| `terraform/modules/openreplay/s3.tf` | 세션 녹화 S3 버킷 |
| `terraform/modules/openreplay/variables.tf` | 입력 변수 |
| `terraform/modules/openreplay/outputs.tf` | 출력 |
| `terraform/modules/openreplay/CLAUDE.md` | 모듈 문서 |
| `cdk/lib/constructs/openreplay.ts` | CDK Construct |
| `docs/decisions/ADR-007-openreplay-session-replay.md` | 아키텍처 결정 기록 |
| `docs/runbooks/14-openreplay-management.md` | 운영 런북 |

### Modified Files

| 경로 | 변경 내용 |
|------|----------|
| `terraform/main.tf` | `module "openreplay"` 호출 추가 |
| `terraform/variables.tf` | `private_subnet_ids` 변수 추가 |
| `terraform/outputs.tf` | OpenReplay 출력 추가 |
| `cdk/lib/rum-pipeline-stack.ts` | OpenReplay Construct 추가 |
| `docs/architecture.md` | Presentation Layer에 OpenReplay 추가 |
| `CLAUDE.md` | Project Structure에 openreplay 모듈 추가 |

---

## 8. Cost Estimate

| 서비스 | 월간 비용 |
|--------|----------|
| EC2 m7g.xlarge (on-demand) | ~$118 |
| RDS db.t4g.medium | ~$50 |
| ElastiCache cache.t4g.micro | ~$12 |
| S3 녹화 데이터 | ~$5 |
| CloudFront | ~$5 |
| ALB | ~$20 |
| **OpenReplay 추가분** | **~$210/월** |
| 기존 RUM Pipeline | ~$124/월 |
| **총 합계** | **~$334/월** |

---

## 9. Verification Plan

### Infrastructure (5 steps)

1. `terraform output -module=openreplay` — 출력값 확인
2. SSM Session → EC2 → `docker compose ps` — 모든 컨테이너 running
3. `aws elbv2 describe-target-health` — ALB 타겟 healthy
4. `curl https://<cf>/` → 302 (SSO 리다이렉트) 확인
5. `curl https://<cf>/ingest/v1/web/not-started` → 200 확인

### Functional (3 steps)

6. SSO 로그인 → 대시보드 → 프로젝트 생성 → projectKey 획득
7. 테스트 페이지에 트래커 삽입 → 세션 녹화 → 대시보드에서 재생 확인
8. `bash scripts/test-ingestion.sh` → 기존 RUM 파이프라인 무영향 검증
