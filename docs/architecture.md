# Architecture

<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

---

# 🇰🇷 한국어

## System Overview

AWS Custom RUM Pipeline은 서버리스 기반 이벤트 수집 및 분석 시스템.
브라우저 SDK(TypeScript) 및 모바일 SDK(iOS Swift, Android Kotlin)가 RUM 이벤트를 수집하고, API Gateway를 통해 AWS 인프라로 전달.
이벤트는 Firehose를 거쳐 S3에 저장되고, Glue/Athena로 쿼리 가능.
Bedrock AgentCore 기반 AI 에이전트가 RUM 데이터를 분석.

## Components

### Ingestion Layer
- **sdk/** — TypeScript RUM SDK. 브라우저에서 페이지뷰, 에러, 사용자 액션 이벤트 수집. esbuild 번들.
- **mobile-sdk-ios/** — iOS RUM SDK (Swift 5.9+, SPM). iOS 15+ 지원. 브라우저 SDK와 동일한 이벤트 스키마.
- **mobile-sdk-android/** — Android RUM SDK (Kotlin 1.9+, Gradle). minSdk 26 지원. 브라우저 SDK와 동일한 이벤트 스키마.
- **terraform/modules/api-gateway/** — HTTP API Gateway. `/ingest` 엔드포인트 노출. Lambda Authorizer 연결.
- **lambda/authorizer/** — JWT/API Key 검증 Lambda Authorizer. 인증 실패 시 403.
- **lambda/ingest/** — HTTP 요청을 Kinesis Firehose로 포워딩하는 브리지 Lambda.

### Storage Layer
- **terraform/modules/firehose/** — Kinesis Data Firehose. S3로 버퍼링 전달. 파티셔닝 설정 포함.
- **terraform/modules/s3-data-lake/** — S3 버킷 3개: raw 이벤트, processed 데이터, Athena 쿼리 결과.

### Processing Layer
- **lambda/transform/** — Firehose 이벤트 변환. JSON 정규화, 스키마 검증.
- **lambda/partition-repair/** — Glue 파티션 자동 복구 (`MSCK REPAIR TABLE`). EventBridge 스케줄 트리거.
- **terraform/modules/partition-repair/** — partition-repair Lambda 인프라.

### Query Layer
- **terraform/modules/glue-catalog/** — AWS Glue 데이터베이스 및 테이블 스키마 정의.
- **lambda/athena-query/** — Athena 쿼리 실행 및 결과 폴링/반환 Lambda.
- **terraform/modules/athena-query/** — athena-query Lambda 인프라.

### Observability Layer
- **terraform/modules/monitoring/** — CloudWatch 대시보드, 알람 (Lambda 에러율, Firehose 지연, API 응답 등).
- **terraform/modules/grafana/** — Amazon Managed Grafana 워크스페이스. Athena 데이터소스 연결.

### Security Layer
- **terraform/modules/security/** — WAF WebACL, API Key 관리, IAM 역할/정책.
- **terraform/modules/auth/** — Cognito User Pool + SSO IdP + Lambda@Edge 인증.
  - CloudFront viewer-request에서 JWT 검증, 미인증 시 Cognito Hosted UI 리다이렉트.
  - `x-user-sub` 헤더로 사용자 식별, AgentCore Memory에서 사용자별 대화 히스토리 분리.

### Analysis Agent
- **agentcore/** — Bedrock AgentCore 기반 RUM 분석 에이전트.
  - `agent.py` — Strands Agent + MCP 도구 연결. Athena 쿼리, 이상 감지, 리포트 생성.
  - `web/` — Next.js 14 Web UI (에이전트 채팅 인터페이스).
  - `web-app/` — 별도 배포 가능한 Next.js 앱.
- **terraform/modules/agent-ui/** — AgentCore UI 호스팅 인프라.

### Session Replay
- **terraform/modules/openreplay/** — OpenReplay 셀프호스팅 인프라. CF → ALB → EC2 (Docker Compose).
  - EC2에서 Kafka, 프론트엔드, 백엔드 컨테이너 실행.
  - RDS PostgreSQL, ElastiCache Redis, S3 녹화 버킷을 외부 관리형으로 사용.
  - `/ingest/*` 경로로 트래커 데이터 수집 (인증 없음), `/*` 대시보드 (SSO).

### Traffic Simulation
- **simulator/** — TypeScript 트래픽 생성기. 실제 브라우저 SDK 호출 시뮬레이션. Docker 컨테이너화.

## Full Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              클라이언트 (SDK)                                    │
│  ┌──────────────┐  ┌──────────────────┐  ┌───────────────────┐                  │
│  │ Web SDK      │  │ iOS SDK (Swift)  │  │ Android SDK       │                  │
│  │ (TypeScript) │  │                  │  │ (Kotlin)          │                  │
│  └──────┬───────┘  └────────┬─────────┘  └─────────┬─────────┘                  │
└─────────┼──────────────────┼───────────────────────┼────────────────────────────┘
          │                  │                       │
          └──────────────────┼───────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           인제스트 파이프라인                                     │
│                                                                                 │
│  ┌─────────┐    ┌──────────────┐    ┌──────────────┐    ┌───────────────────┐   │
│  │  WAF    │───▶│ API Gateway  │───▶│   Lambda     │───▶│ Kinesis Firehose  │   │
│  │ WebACL  │    │ (HTTP API)   │    │ Authorizer   │    │                   │   │
│  │ - Rate  │    │              │    │ (API Key/SSM)│    │ - 동적 파티셔닝    │   │
│  │ - Bot   │    │ POST         │    └──────────────┘    │ - Parquet 변환    │   │
│  └─────────┘    │ /v1/events   │                        │                   │   │
│                 │ /v1/events/  │    ┌──────────────┐    │                   │   │
│                 │   beacon     │───▶│   Lambda     │◀───│                   │   │
│                 └──────────────┘    │   Ingest     │    └────────┬──────────┘   │
│                                    │ (→ Firehose)  │             │              │
│                                    └──────────────┘    ┌────────┼──────────┐   │
│                                                        │        ▼          │   │
│                                                        │  Lambda Transform │   │
│                                                        │  (JSON → Parquet) │   │
│                                                        │  (PII 제거)       │   │
│                                                        └───────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                                                  │
                                                                  ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            스토리지 & 카탈로그                                    │
│                                                                                 │
│  ┌───────────────────────────────────────┐    ┌────────────────────────────┐    │
│  │          S3 Data Lake                 │    │      Glue Catalog          │    │
│  │                                       │    │                            │    │
│  │  raw/platform=web/year/month/day/hour │    │  DB: rum_pipeline_db       │    │
│  │  aggregated/hourly/                   │    │  ├─ rum_events             │    │
│  │  aggregated/daily/                    │    │  ├─ rum_hourly_metrics     │    │
│  │  athena-results/                      │    │  └─ rum_daily_summary      │    │
│  │  errors/                              │    │                            │    │
│  └───────────────────────────────────────┘    └────────────────────────────┘    │
│                                                            ▲                    │
│                          ┌─────────────────────────────────┘                    │
│                          │                                                      │
│                 ┌────────┴────────┐                                             │
│                 │ Lambda          │   EventBridge (15분 간격)                     │
│                 │ Partition Repair│◀── rate(15 minutes)                          │
│                 │ (MSCK REPAIR)  │                                               │
│                 └────────────────┘                                               │
└─────────────────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          쿼리 & 시각화                                           │
│                                                                                 │
│  ┌───────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐   │
│  │ Athena Workgroup  │    │ Amazon Managed       │    │ CloudWatch          │   │
│  │ rum-pipeline-     │───▶│ Grafana              │    │ Dashboard           │   │
│  │ athena            │    │                      │    │                     │   │
│  │                   │    │ - 핵심 KPI (8)       │    │ - API 요청/에러      │   │
│  │ - 100GB 스캔 제한  │    │ - Core Web Vitals    │    │ - Lambda 호출/에러   │   │
│  │ - Parquet 쿼리    │    │ - 에러 & 크래시      │    │ - WAF 허용/차단      │   │
│  └─────────┬─────────┘    │ - 리소스/네트워크     │    │ - Firehose 수신/전송 │   │
│            │              │ - 모바일 바이탈        │    │ - 22개 위젯         │   │
│            │              │ - 사용자/세션 탐색기   │    └─────────────────────┘   │
│            │              │ 43패널 9섹션 (KST)    │                              │
│            │              │ SSO 인증              │                              │
│            │              └──────────────────────┘                              │
└────────────┼────────────────────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        AI 분석 에이전트 (Agent UI)                                │
│                                                                                 │
│  ┌───────────┐   ┌─────────────┐   ┌─────────┐   ┌──────────────────────────┐  │
│  │ CloudFront│──▶│ Lambda@Edge │──▶│  ALB    │──▶│ EC2 (t4g.large)         │  │
│  │           │   │ viewer-req  │   │ (HTTP)  │   │                          │  │
│  │ HTTPS     │   │             │   │         │   │ Next.js 14 Chat UI       │  │
│  │           │   │ JWT 검증    │   │ SG:     │   │ ├─ /api/chat (SSE)       │  │
│  │           │   │ ┌─────────┐ │   │ CF only │   │ │  └─ Bedrock Claude     │  │
│  │           │   │ │ Cognito │ │   │         │   │ │     Sonnet 4            │  │
│  │           │   │ │ User    │ │   └─────────┘   │ │  └─ Athena Query Lambda│  │
│  │           │   │ │ Pool    │ │                  │ │     (SQL 자동 생성/실행) │  │
│  │           │   │ │ + SSO   │ │                  │ │                         │  │
│  │           │   │ │ IdP     │ │                  │ └─ x-user-sub 헤더       │  │
│  │           │   │ └─────────┘ │                  │    └─ 사용자별 Memory     │  │
│  └───────────┘   │             │                  │                          │  │
│                  │ x-user-sub  │                  │ ┌──────────────────────┐  │  │
│                  │ 헤더 주입    │                  │ │ Bedrock AgentCore    │  │  │
│                  └─────────────┘                  │ │ - Runtime            │  │  │
│                                                   │ │ - Gateway (Athena)   │  │  │
│                                                   │ │ - Memory (per-user)  │  │  │
│                                                   │ └──────────────────────┘  │  │
│                                                   └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              인프라 관리 (IaC)                                   │
│                                                                                 │
│  ┌──────────────────────────┐    ┌──────────────────────────┐                   │
│  │ Terraform (HCL)          │    │ CDK (TypeScript)          │                   │
│  │ 11개 모듈:               │    │ 11개 Construct:           │                   │
│  │ s3-data-lake, glue,      │    │ S3DataLake, GlueCatalog,  │                   │
│  │ firehose, api-gateway,   │    │ Firehose, ApiGateway,     │                   │
│  │ security, monitoring,    │    │ Security, Monitoring,     │                   │
│  │ grafana, partition-repair│    │ Grafana, PartitionRepair, │                   │
│  │ athena-query, agent-ui,  │    │ AthenaQuery, AgentUi,     │                   │
│  │ auth                     │    │ Auth                      │                   │
│  └──────────────────────────┘    └──────────────────────────┘                   │
│                                                                                 │
│  State: S3 + DynamoDB Lock          Lambda 소스 공유 (lambda/)                   │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              테스트 & 시뮬레이션                                  │
│                                                                                 │
│  ┌─────────────────────────┐    ┌──────────────────────────────────┐            │
│  │ Simulator (TypeScript)  │    │ EKS CronJob (5분 간격)            │            │
│  │ - Web 60%               │    │ - rum-simulator 컨테이너          │            │
│  │ - iOS 25%               │    │ - ECR 이미지                      │            │
│  │ - Android 15%           │    │ - API Key Secret                  │            │
│  │ - Docker 컨테이너       │    └──────────────────────────────────┘            │
│  └─────────────────────────┘                                                    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Summary

```
SDK → WAF → API GW → Authorizer → Ingest Lambda → Firehose → Transform Lambda → S3 (Parquet)
                                                                                      │
                                              ┌───────────────────────────────────────┘
                                              ▼
                                   Glue Catalog ← Partition Repair (15분)
                                              │
                              ┌───────────────┼───────────────┐
                              ▼               ▼               ▼
                          Grafana      CloudWatch       Agent UI
                         (시각화)      (운영 모니터링)   (AI 분석)
                                                              │
                                                    Bedrock Claude Sonnet
                                                    + Athena SQL 자동 생성
                                                    + Per-User Memory
```

## Infrastructure

### AWS Region
- ap-northeast-2 (서울)

### Terraform Modules (terraform/modules/)
| 모듈 | 리소스 | 설명 |
|------|--------|------|
| s3-data-lake | S3 Buckets | raw, processed, athena-results |
| glue-catalog | Glue DB + Table | rum_events 스키마 |
| firehose | Kinesis Firehose | S3 delivery, transform Lambda 연결 |
| api-gateway | HTTP API, Lambda Integration | /ingest POST |
| security | WAF, API Key, IAM | 인증/인가 인프라 |
| monitoring | CloudWatch | 대시보드, 알람 |
| grafana | AMG Workspace | Athena 데이터소스 |
| partition-repair | Lambda, EventBridge | 파티션 자동 복구 |
| athena-query | Lambda | 쿼리 실행 API |
| agent-ui | CloudFront + ALB + EC2 | AgentCore Web UI 호스팅 |
| auth | Cognito, Lambda@Edge | SSO 인증 + JWT 검증 |

### Deployed Resources (ap-northeast-2)
- API Endpoint: `https://<api-id>.execute-api.ap-northeast-2.amazonaws.com`
- Grafana: `https://<workspace-id>.grafana-workspace.ap-northeast-2.amazonaws.com/d/rum-unified-v2`
- Agent UI: `https://<distribution-id>.cloudfront.net`
- SSO Portal: `https://<directory-id>.awsapps.com/start`
- SSM Parameter: `/rum-pipeline/dev/api-keys`

### CDK (TypeScript 대안)
| Construct | Terraform 대응 | 설명 |
|-----------|---------------|------|
| S3DataLake | s3-data-lake | S3 버킷 + 생명주기 |
| GlueCatalog | glue-catalog | Glue DB + 3개 테이블 |
| Firehose | firehose | Firehose + Transform Lambda |
| Security | security | WAF + SSM + Authorizer |
| ApiGateway | api-gateway | HTTP API + Ingest Lambda |
| Grafana | grafana | Managed Grafana + Athena WG |
| Monitoring | monitoring | CloudWatch Dashboard |
| PartitionRepair | partition-repair | 파티션 복구 + EventBridge |
| AthenaQuery | athena-query | Athena Query Lambda |
| AgentUi | agent-ui | CloudFront + ALB + EC2 |
| Auth | auth | Cognito + SSO + Lambda@Edge |

CDK 명령: `cd cdk && npx cdk synth / deploy / diff`

## Key Design Decisions

- Firehose를 중간 버퍼로 사용해 Lambda throttling 없이 고처리량 지원
- Lambda Authorizer로 API Key 검증을 Gateway 레벨에서 처리
- Glue 파티션을 날짜 기준으로 구성해 Athena 쿼리 비용 최소화
- Bedrock AgentCore로 에이전트 인프라 관리 부담 제거
- CloudFront + Lambda@Edge + Cognito SSO로 인프라 레벨 인증 (앱 코드 변경 최소)
- Cognito sub 클레임을 session_id로 사용하여 사용자별 AgentCore Memory 분리
- Grafana 대시보드 날짜 필터를 KST(Asia/Seoul) 기준으로 처리 (UTC 오차 방지)
- Terraform + CDK 듀얼 IaC로 팀별 선호 도구 선택 가능 (Lambda 소스 공유)

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

---

# 🇺🇸 English

## System Overview

AWS Custom RUM Pipeline is a serverless event collection and analytics system.
Browser SDK (TypeScript) and mobile SDKs (iOS Swift, Android Kotlin) collect RUM events and deliver them to AWS infrastructure via API Gateway.
Events are stored in S3 through Firehose and made queryable via Glue/Athena.
A Bedrock AgentCore-based AI agent analyzes the RUM data.

## Components

### Ingestion Layer
- **sdk/** — TypeScript RUM SDK. Collects page views, errors, and user action events from the browser. Bundled with esbuild.
- **mobile-sdk-ios/** — iOS RUM SDK (Swift 5.9+, SPM). Supports iOS 15+. Same event schema as the browser SDK.
- **mobile-sdk-android/** — Android RUM SDK (Kotlin 1.9+, Gradle). Supports minSdk 26. Same event schema as the browser SDK.
- **terraform/modules/api-gateway/** — HTTP API Gateway. Exposes the `/ingest` endpoint. Connected to Lambda Authorizer.
- **lambda/authorizer/** — JWT/API Key validation Lambda Authorizer. Returns 403 on authentication failure.
- **lambda/ingest/** — Bridge Lambda that forwards HTTP requests to Kinesis Firehose.

### Storage Layer
- **terraform/modules/firehose/** — Kinesis Data Firehose. Buffered delivery to S3. Includes partitioning configuration.
- **terraform/modules/s3-data-lake/** — 3 S3 buckets: raw events, processed data, Athena query results.

### Processing Layer
- **lambda/transform/** — Firehose event transformation. JSON normalization, schema validation.
- **lambda/partition-repair/** — Automatic Glue partition repair (`MSCK REPAIR TABLE`). Triggered by EventBridge schedule.
- **terraform/modules/partition-repair/** — partition-repair Lambda infrastructure.

### Query Layer
- **terraform/modules/glue-catalog/** — AWS Glue database and table schema definitions.
- **lambda/athena-query/** — Lambda for executing Athena queries and polling/returning results.
- **terraform/modules/athena-query/** — athena-query Lambda infrastructure.

### Observability Layer
- **terraform/modules/monitoring/** — CloudWatch dashboards, alarms (Lambda error rate, Firehose latency, API response, etc.).
- **terraform/modules/grafana/** — Amazon Managed Grafana workspace. Connected to Athena data source.

### Security Layer
- **terraform/modules/security/** — WAF WebACL, API Key management, IAM roles/policies.
- **terraform/modules/auth/** — Cognito User Pool + SSO IdP + Lambda@Edge authentication.
  - JWT validation at CloudFront viewer-request; redirects to Cognito Hosted UI when unauthenticated.
  - User identification via `x-user-sub` header; per-user conversation history isolation in AgentCore Memory.

### Analysis Agent
- **agentcore/** — Bedrock AgentCore-based RUM analysis agent.
  - `agent.py` — Strands Agent + MCP tool integration. Athena queries, anomaly detection, report generation.
  - `web/` — Next.js 14 Web UI (agent chat interface).
  - `web-app/` — Independently deployable Next.js app.
- **terraform/modules/agent-ui/** — AgentCore UI hosting infrastructure.

### Session Replay
- **terraform/modules/openreplay/** — Self-hosted OpenReplay infrastructure. CF → ALB → EC2 (Docker Compose).
  - Runs Kafka, frontend, backend containers on EC2.
  - Uses RDS PostgreSQL, ElastiCache Redis, S3 recording bucket as external managed services.
  - `/ingest/*` path for tracker data collection (no auth), `/*` dashboard (SSO).

### Traffic Simulation
- **simulator/** — TypeScript traffic generator. Simulates actual browser SDK calls. Dockerized.

## Full Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Clients (SDK)                                      │
│  ┌──────────────┐  ┌──────────────────┐  ┌───────────────────┐                  │
│  │ Web SDK      │  │ iOS SDK (Swift)  │  │ Android SDK       │                  │
│  │ (TypeScript) │  │                  │  │ (Kotlin)          │                  │
│  └──────┬───────┘  └────────┬─────────┘  └─────────┬─────────┘                  │
└─────────┼──────────────────┼───────────────────────┼────────────────────────────┘
          │                  │                       │
          └──────────────────┼───────────────────────┘
                             ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                           Ingestion Pipeline                                    │
│                                                                                 │
│  ┌─────────┐    ┌──────────────┐    ┌──────────────┐    ┌───────────────────┐   │
│  │  WAF    │───▶│ API Gateway  │───▶│   Lambda     │───▶│ Kinesis Firehose  │   │
│  │ WebACL  │    │ (HTTP API)   │    │ Authorizer   │    │                   │   │
│  │ - Rate  │    │              │    │ (API Key/SSM)│    │ - Dynamic         │   │
│  │ - Bot   │    │ POST         │    └──────────────┘    │   Partitioning    │   │
│  └─────────┘    │ /v1/events   │                        │ - Parquet         │   │
│                 │ /v1/events/  │    ┌──────────────┐    │   Conversion      │   │
│                 │   beacon     │───▶│   Lambda     │◀───│                   │   │
│                 └──────────────┘    │   Ingest     │    └────────┬──────────┘   │
│                                    │ (→ Firehose)  │             │              │
│                                    └──────────────┘    ┌────────┼──────────┐   │
│                                                        │        ▼          │   │
│                                                        │  Lambda Transform │   │
│                                                        │  (JSON → Parquet) │   │
│                                                        │  (PII Removal)    │   │
│                                                        └───────────────────┘   │
└─────────────────────────────────────────────────────────────────────────────────┘
                                                                  │
                                                                  ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                            Storage & Catalog                                    │
│                                                                                 │
│  ┌───────────────────────────────────────┐    ┌────────────────────────────┐    │
│  │          S3 Data Lake                 │    │      Glue Catalog          │    │
│  │                                       │    │                            │    │
│  │  raw/platform=web/year/month/day/hour │    │  DB: rum_pipeline_db       │    │
│  │  aggregated/hourly/                   │    │  ├─ rum_events             │    │
│  │  aggregated/daily/                    │    │  ├─ rum_hourly_metrics     │    │
│  │  athena-results/                      │    │  └─ rum_daily_summary      │    │
│  │  errors/                              │    │                            │    │
│  └───────────────────────────────────────┘    └────────────────────────────┘    │
│                                                            ▲                    │
│                          ┌─────────────────────────────────┘                    │
│                          │                                                      │
│                 ┌────────┴────────┐                                             │
│                 │ Lambda          │   EventBridge (every 15 min)                 │
│                 │ Partition Repair│◀── rate(15 minutes)                          │
│                 │ (MSCK REPAIR)  │                                               │
│                 └────────────────┘                                               │
└─────────────────────────────────────────────────────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                          Query & Visualization                                  │
│                                                                                 │
│  ┌───────────────────┐    ┌──────────────────────┐    ┌─────────────────────┐   │
│  │ Athena Workgroup  │    │ Amazon Managed       │    │ CloudWatch          │   │
│  │ rum-pipeline-     │───▶│ Grafana              │    │ Dashboard           │   │
│  │ athena            │    │                      │    │                     │   │
│  │                   │    │ - KPI (8 stats)      │    │ - API Req/Errors    │   │
│  │ - 100GB Scan      │    │ - Core Web Vitals    │    │ - Lambda Invoc/Err  │   │
│  │   Limit           │    │ - Errors & Crashes   │    │ - WAF Allow/Block   │   │
│  └─────────┬─────────┘    │ - Resources/Network  │    │ - Firehose In/Out   │   │
│            │              │ - Mobile Vitals       │    │ - 22 Widgets        │   │
│            │              │ - User/Session Expl.  │    └─────────────────────┘   │
│            │              │ 43 panels, 9 sections │                              │
│            │              │ (KST timezone)        │                              │
│            │              │ SSO Auth             │                              │
│            │              └──────────────────────┘                              │
└────────────┼────────────────────────────────────────────────────────────────────┘
             │
             ▼
┌─────────────────────────────────────────────────────────────────────────────────┐
│                        AI Analysis Agent (Agent UI)                              │
│                                                                                 │
│  ┌───────────┐   ┌─────────────┐   ┌─────────┐   ┌──────────────────────────┐  │
│  │ CloudFront│──▶│ Lambda@Edge │──▶│  ALB    │──▶│ EC2 (t4g.large)         │  │
│  │           │   │ viewer-req  │   │ (HTTP)  │   │                          │  │
│  │ HTTPS     │   │             │   │         │   │ Next.js 14 Chat UI       │  │
│  │           │   │ JWT Verify  │   │ SG:     │   │ ├─ /api/chat (SSE)       │  │
│  │           │   │ ┌─────────┐ │   │ CF only │   │ │  └─ Bedrock Claude     │  │
│  │           │   │ │ Cognito │ │   │         │   │ │     Sonnet 4            │  │
│  │           │   │ │ User    │ │   └─────────┘   │ │  └─ Athena Query Lambda│  │
│  │           │   │ │ Pool    │ │                  │ │     (Auto SQL Gen/Exec)│  │
│  │           │   │ │ + SSO   │ │                  │ │                         │  │
│  │           │   │ │ IdP     │ │                  │ └─ x-user-sub Header     │  │
│  │           │   │ └─────────┘ │                  │    └─ Per-User Memory    │  │
│  └───────────┘   │             │                  │                          │  │
│                  │ x-user-sub  │                  │ ┌──────────────────────┐  │  │
│                  │ Header      │                  │ │ Bedrock AgentCore    │  │  │
│                  │ Injection   │                  │ │ - Runtime            │  │  │
│                  └─────────────┘                  │ │ - Gateway (Athena)   │  │  │
│                                                   │ │ - Memory (per-user)  │  │  │
│                                                   │ └──────────────────────┘  │  │
│                                                   └──────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                          Infrastructure Management (IaC)                        │
│                                                                                 │
│  ┌──────────────────────────┐    ┌──────────────────────────┐                   │
│  │ Terraform (HCL)          │    │ CDK (TypeScript)          │                   │
│  │ 11 Modules:              │    │ 11 Constructs:            │                   │
│  │ s3-data-lake, glue,      │    │ S3DataLake, GlueCatalog,  │                   │
│  │ firehose, api-gateway,   │    │ Firehose, ApiGateway,     │                   │
│  │ security, monitoring,    │    │ Security, Monitoring,     │                   │
│  │ grafana, partition-repair│    │ Grafana, PartitionRepair, │                   │
│  │ athena-query, agent-ui,  │    │ AthenaQuery, AgentUi,     │                   │
│  │ auth                     │    │ Auth                      │                   │
│  └──────────────────────────┘    └──────────────────────────┘                   │
│                                                                                 │
│  State: S3 + DynamoDB Lock          Shared Lambda Source (lambda/)              │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              Testing & Simulation                               │
│                                                                                 │
│  ┌─────────────────────────┐    ┌──────────────────────────────────┐            │
│  │ Simulator (TypeScript)  │    │ EKS CronJob (every 5 min)        │            │
│  │ - Web 60%               │    │ - rum-simulator container         │            │
│  │ - iOS 25%               │    │ - ECR image                       │            │
│  │ - Android 15%           │    │ - API Key Secret                  │            │
│  │ - Docker container      │    └──────────────────────────────────┘            │
│  └─────────────────────────┘                                                    │
└─────────────────────────────────────────────────────────────────────────────────┘
```

## Data Flow Summary

```
SDK → WAF → API GW → Authorizer → Ingest Lambda → Firehose → Transform Lambda → S3 (Parquet)
                                                                                      │
                                              ┌───────────────────────────────────────┘
                                              ▼
                                   Glue Catalog ← Partition Repair (15 min)
                                              │
                              ┌───────────────┼───────────────┐
                              ▼               ▼               ▼
                          Grafana      CloudWatch       Agent UI
                       (Visualization) (Ops Monitoring) (AI Analysis)
                                                              │
                                                    Bedrock Claude Sonnet
                                                    + Auto Athena SQL Generation
                                                    + Per-User Memory
```

## Infrastructure

### AWS Region
- ap-northeast-2 (Seoul)

### Terraform Modules (terraform/modules/)
| Module | Resources | Description |
|--------|-----------|-------------|
| s3-data-lake | S3 Buckets | raw, processed, athena-results |
| glue-catalog | Glue DB + Table | rum_events schema |
| firehose | Kinesis Firehose | S3 delivery, transform Lambda integration |
| api-gateway | HTTP API, Lambda Integration | /ingest POST |
| security | WAF, API Key, IAM | Authentication/authorization infrastructure |
| monitoring | CloudWatch | Dashboards, alarms |
| grafana | AMG Workspace | Athena data source |
| partition-repair | Lambda, EventBridge | Automatic partition repair |
| athena-query | Lambda | Query execution API |
| agent-ui | CloudFront + ALB + EC2 | AgentCore Web UI hosting |
| auth | Cognito, Lambda@Edge | SSO authentication + JWT validation |

### Deployed Resources (ap-northeast-2)
- API Endpoint: `https://<api-id>.execute-api.ap-northeast-2.amazonaws.com`
- Grafana: `https://<workspace-id>.grafana-workspace.ap-northeast-2.amazonaws.com/d/rum-unified-v2`
- Agent UI: `https://<distribution-id>.cloudfront.net`
- SSO Portal: `https://<directory-id>.awsapps.com/start`
- SSM Parameter: `/rum-pipeline/dev/api-keys`

### CDK (TypeScript Alternative)
| Construct | Terraform Equivalent | Description |
|-----------|---------------------|-------------|
| S3DataLake | s3-data-lake | S3 buckets + lifecycle |
| GlueCatalog | glue-catalog | Glue DB + 3 tables |
| Firehose | firehose | Firehose + Transform Lambda |
| Security | security | WAF + SSM + Authorizer |
| ApiGateway | api-gateway | HTTP API + Ingest Lambda |
| Grafana | grafana | Managed Grafana + Athena WG |
| Monitoring | monitoring | CloudWatch Dashboard |
| PartitionRepair | partition-repair | Partition repair + EventBridge |
| AthenaQuery | athena-query | Athena Query Lambda |
| AgentUi | agent-ui | CloudFront + ALB + EC2 |
| Auth | auth | Cognito + SSO + Lambda@Edge |

CDK commands: `cd cdk && npx cdk synth / deploy / diff`

## Key Design Decisions

- Firehose as an intermediate buffer to support high throughput without Lambda throttling
- Lambda Authorizer validates API Keys at the Gateway level
- Glue partitions organized by date to minimize Athena query costs
- Bedrock AgentCore eliminates the burden of managing agent infrastructure
- CloudFront + Lambda@Edge + Cognito SSO for infrastructure-level authentication (minimal app code changes)
- Cognito sub claim used as session_id for per-user AgentCore Memory isolation
- Grafana dashboard date filters use KST (Asia/Seoul) timezone to prevent UTC offset issues
- Dual IaC with Terraform + CDK for team tool preference flexibility (shared Lambda source)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
