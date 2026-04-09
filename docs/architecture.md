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
- **terraform/modules/api-gateway/** — HTTP API Gateway. `POST /v1/events`, `POST /v1/events/beacon` 엔드포인트. Lambda Authorizer 연결.
- **lambda/authorizer/** — JWT/API Key 검증 Lambda Authorizer. 인증 실패 시 403.
- **lambda/ingest/** — HTTP 요청을 Kinesis Firehose로 포워딩하는 브리지 Lambda.

### Storage Layer
- **terraform/modules/firehose/** — Kinesis Data Firehose. 동적 파티셔닝(platform/year/month/day/hour) + JSON→Parquet 변환. Transform Lambda 연결.
- **terraform/modules/s3-data-lake/** — 단일 S3 데이터 레이크 버킷. `raw/`, `aggregated/`, `athena-results/`, `errors/` 프리픽스. KMS 암호화, 생명주기 관리.

### Processing Layer
- **lambda/transform/** — Firehose 이벤트 변환. JSON 정규화, 스키마 검증, PII 제거, 파티션 키 생성.
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
- **terraform/modules/security/** — WAF WebACL (Rate Limit + Bot Control), API Key 관리, IAM 역할/정책.
- **terraform/modules/auth/** — Cognito User Pool + SSO IdP + Lambda@Edge 인증.
  - CloudFront viewer-request에서 JWT 검증, 미인증 시 Cognito Hosted UI 리다이렉트.
  - `x-user-sub` 헤더로 사용자 식별, AgentCore Memory에서 사용자별 대화 히스토리 분리.
- **lambda/edge-auth/** — CloudFront Lambda@Edge JWT 검증 함수 (Node.js 20). 토큰 교환, 로그아웃 처리.

### Analysis Agent
- **agentcore/** — Bedrock AgentCore 기반 RUM 분석 에이전트.
  - `agent.py` — Strands Agent (Claude Sonnet 4.6) + 8개 도구. AgentCore Runtime 컨테이너에서 실행.
  - `proxy.py` — EC2에서 실행되는 경량 HTTP 프록시. boto3 `invoke-agent-runtime`으로 AgentCore Runtime 호출, SSE 스트리밍 중계.
  - `web-app/` — Next.js 14 Web UI. route.ts는 proxy.py의 SSE 프록시 역할 (~46줄).
- **AgentCore 관리형 서비스:**
  - **Runtime** — agent.py 컨테이너 호스팅 (ECR 이미지, 자동 스케일링)
  - **Gateway** — MCP 프로토콜로 Athena Query Lambda 연결 (`rum-athena-gw`)
  - **Memory** — 사용자별 대화 히스토리 저장 (`rum_analysis_memory`, session_id=x-user-sub)
- **terraform/modules/agent-ui/** — Agent UI 호스팅 인프라 (CloudFront + ALB + EC2 + proxy.py systemd)

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
│                        AI 분석 에이전트 (Agent UI → AgentCore)                    │
│                                                                                 │
│  ┌───────────┐   ┌─────────────┐   ┌─────────┐   ┌──────────────────────────┐  │
│  │ CloudFront│──▶│ Lambda@Edge │──▶│  ALB    │──▶│ EC2 (t4g.large)         │  │
│  │ (HTTPS)   │   │ (JWT 검증)  │   │ (180s)  │   │                          │  │
│  └───────────┘   │ ┌─────────┐ │   │ SG:     │   │ Next.js :3000            │  │
│                  │ │ Cognito │ │   │ CF only │   │  └─ route.ts (SSE 프록시) │  │
│                  │ │ SSO IdP │ │   └─────────┘   │       │                   │  │
│                  │ └─────────┘ │                  │       ▼                   │  │
│                  │ x-user-sub  │                  │ proxy.py :8080            │  │
│                  │ 헤더 주입    │                  │  └─ boto3 invoke          │  │
│                  └─────────────┘                  │     -agent-runtime        │  │
│                                                   └──────────┬───────────────┘  │
│                                                              │ SigV4            │
│  ┌───────────────────────────────────────────────────────────▼───────────────┐  │
│  │                    Bedrock AgentCore (관리형 서비스)                        │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │ Runtime (rumAnalysisAgent)                                          │  │  │
│  │  │  agent.py — Strands Agent (Claude Sonnet 4.6)                      │  │  │
│  │  │  ├─ StreamingHook → SSE 이벤트 (status, chunk, done)               │  │  │
│  │  │  ├─ MemoryHook → 대화 히스토리 자동 저장/로드                        │  │  │
│  │  │  └─ 8개 도구 (MCP Gateway 1개 + boto3 직접 7개)                     │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  │  ┌──────────────────────┐  ┌───────────────────────────────────────────┐  │  │
│  │  │ Memory               │  │ Gateway (rum-athena-gw)                   │  │  │
│  │  │ rum_analysis_memory  │  │  └─ Target: athena-query                  │  │  │
│  │  │ session_id =         │  │     └─ Lambda: rum-pipeline-athena-query  │  │  │
│  │  │   x-user-sub         │  │        MCP Tool: query_athena(sql)        │  │  │
│  │  │ (사용자별 격리)       │  │        → Athena SQL 실행 + 결과 반환       │  │  │
│  │  └──────────────────────┘  └───────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                              인프라 관리 (IaC)                                   │
│                                                                                 │
│  ┌──────────────────────────┐    ┌──────────────────────────┐                   │
│  │ Terraform (HCL)          │    │ CDK (TypeScript)          │                   │
│  │ 12개 모듈:               │    │ 12개 Construct:           │                   │
│  │ s3-data-lake, glue,      │    │ S3DataLake, GlueCatalog,  │                   │
│  │ firehose, api-gateway,   │    │ Firehose, ApiGateway,     │                   │
│  │ security, monitoring,    │    │ Security, Monitoring,     │                   │
│  │ grafana, partition-repair│    │ Grafana, PartitionRepair, │                   │
│  │ athena-query, agent-ui,  │    │ AthenaQuery, AgentUi,     │                   │
│  │ auth, openreplay         │    │ Auth, OpenReplay          │                   │
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
```

## AI 분석 요청 흐름 (사용자 → AgentCore)

```
사용자 (브라우저)
  │ POST /api/chat { prompt: "오늘 RUM 현황을 알려줘" }
  ▼
CloudFront (HTTPS) → Lambda@Edge (JWT 검증, x-user-sub 헤더 주입) → ALB (idle 180초)
  │
  ▼
EC2 Next.js route.ts :3000 (SSE 프록시, ~46줄)
  │ fetch("http://localhost:8080/invocations", { prompt, session_id: x-user-sub })
  ▼
EC2 proxy.py :8080 (systemd: rum-agent.service)
  │ boto3.client("bedrock-agentcore").invoke_agent_runtime(
  │     agentRuntimeArn=".../rumAnalysisAgent-...",
  │     qualifier="rumAgentEndpoint",
  │     payload=b'{"prompt":"...","session_id":"..."}'
  │ )
  │ → resp["response"].iter_chunks() → SSE 중계
  ▼
AgentCore Runtime (관리형, 컨테이너: rum-agent:latest)
  │ @app.entrypoint async def invoke()
  │   ① MemoryHook: AgentCore Memory에서 최근 5턴 대화 로드 (session_id=x-user-sub)
  │   ② StreamingHook: 도구 실행 상태를 SSE 이벤트로 push
  │   ③ MCP Gateway 연결 (SigV4, Athena Query Lambda 도구 발견)
  ▼
Strands Agent (Claude Sonnet 4.6, Bedrock Converse API, native tool_use)
  │
  ├── [MCP Gateway 경유] query_athena(sql)
  │     → rum-athena-gw → Lambda:rum-pipeline-athena-query → Athena
  │     → SQL: SELECT ... FROM rum_pipeline_db.rum_events WHERE year/month/day
  │
  ├── [boto3 직접 호출] search_logs(log_group, pattern)    → CloudWatch Logs
  ├── [boto3 직접 호출] get_metrics(namespace, metric)     → CloudWatch Metrics
  ├── [boto3 직접 호출] describe_alarms(state)             → CloudWatch Alarms
  ├── [boto3 직접 호출] select_s3_object(key, expression)  → S3 Select
  ├── [boto3 직접 호출] get_table_schema(table)            → Glue Catalog
  ├── [boto3 직접 호출] create_grafana_annotation(text)    → Grafana API
  └── [boto3 직접 호출] publish_sns(message)               → SNS Publish
  │
  ▼
SSE 응답 스트림 (역방향)
  agent.py yield → AgentCore Runtime → proxy.py iter_chunks → route.ts passthrough → 브라우저
    {"type": "start"}
    {"type": "status", "content": "Athena 분석 중..."}
    {"type": "status", "content": "✅ Athena 완료"}
    {"type": "heartbeat"}                                   ← 15초 간격
    {"type": "chunk", "content": "## 오늘 RUM 현황..."}     ← 마크다운 분석 리포트
    {"type": "done"}
```

### AgentCore Gateway 구성

```
rum-athena-gw (MCP 프로토콜, IAM 인증)
  └── Target: athena-query (READY)
        ├── Lambda: rum-pipeline-athena-query
        │   (비동기 Athena 쿼리: 실행 → 폴링 → 결과 반환)
        └── MCP Tool: query_athena
              ├── 입력: { "sql": "SELECT ... FROM rum_pipeline_db.rum_events WHERE ..." }
              ├── 제약: SELECT만 허용, year/month/day 파티션 필터 필수
              └── 금지 함수: COUNTIF→COUNT_IF, SAFE_DIVIDE→TRY, IFNULL→COALESCE
```

### 사용자별 격리

```
사용자 A (Cognito sub: "aaa") → Lambda@Edge x-user-sub: "aaa"
  → proxy.py session_id: "aaa" → AgentCore Memory: 사용자 A 대화만 로드/저장

사용자 B (Cognito sub: "bbb") → Lambda@Edge x-user-sub: "bbb"
  → proxy.py session_id: "bbb" → AgentCore Memory: 사용자 B 대화만 로드/저장
```

## Infrastructure

### AWS Region
- ap-northeast-2 (서울)

### Terraform Modules (terraform/modules/)
| 모듈 | 리소스 | 설명 |
|------|--------|------|
| s3-data-lake | S3 Bucket | 단일 버킷 (raw/, aggregated/, athena-results/, errors/ 프리픽스) |
| glue-catalog | Glue DB + 3 Tables | rum_events, rum_hourly_metrics, rum_daily_summary |
| firehose | Kinesis Firehose | 동적 파티셔닝 + Parquet 변환, Transform Lambda |
| api-gateway | HTTP API, Lambda Integration | POST /v1/events, /v1/events/beacon |
| security | WAF, API Key, IAM | 인증/인가 인프라 |
| monitoring | CloudWatch | 대시보드, 알람 |
| grafana | AMG Workspace | Athena 데이터소스 |
| partition-repair | Lambda, EventBridge | 파티션 자동 복구 |
| athena-query | Lambda | 쿼리 실행 API |
| agent-ui | CloudFront + ALB + EC2 | AgentCore Web UI 호스팅 |
| auth | Cognito, Lambda@Edge | SSO 인증 + JWT 검증 |
| openreplay | CloudFront, ALB, EC2, RDS, ElastiCache, S3 | 세션 리플레이 (셀프호스팅 OpenReplay) |

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
| OpenReplay | openreplay | 세션 리플레이 (CF + ALB + EC2 + RDS + Redis + S3) |

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
- OpenReplay 셀프호스팅으로 세션 리플레이 데이터 주권 확보 (SaaS 대비 비용 절감, RDS+Redis+S3 외부 관리형)
- Agent UI ALB idle_timeout 180초 + SSE heartbeat(15초 간격)로 멀티라운드 AI 분석 타임아웃 방지
- Athena/Trino 금지 함수 목록 (COUNTIF, SAFE_DIVIDE, IFNULL, IF, GROUP_CONCAT)으로 SQL 호환성 보장
- 에이전트 도구 호출 제한 (라운드당 최대 2개)으로 불필요한 API 호출 방지 및 비용 최적화
- Agent UI PDF/Word 리포트 다운로드는 DOM clone 방식으로 서버 사이드 렌더링 없이 구현
- EC2 proxy.py → AgentCore Runtime invoke API로 에이전트 호출 (route.ts는 SSE 프록시만, 코드 중복 제거)
- MCP Gateway로 Athena만 연결, 나머지 7개 도구는 agent.py에서 boto3 직접 호출 (비동기 쿼리만 Lambda 캡슐화)
- AgentCore Runtime 컨테이너로 agent.py 배포, ECR 이미지 버전 관리로 무중단 업데이트

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
- **terraform/modules/api-gateway/** — HTTP API Gateway. `POST /v1/events`, `POST /v1/events/beacon` endpoints. Connected to Lambda Authorizer.
- **lambda/authorizer/** — JWT/API Key validation Lambda Authorizer. Returns 403 on authentication failure.
- **lambda/ingest/** — Bridge Lambda that forwards HTTP requests to Kinesis Firehose.

### Storage Layer
- **terraform/modules/firehose/** — Kinesis Data Firehose. Dynamic partitioning (platform/year/month/day/hour) + JSON→Parquet conversion. Transform Lambda integration.
- **terraform/modules/s3-data-lake/** — Single S3 data lake bucket. `raw/`, `aggregated/`, `athena-results/`, `errors/` prefixes. KMS encryption, lifecycle management.

### Processing Layer
- **lambda/transform/** — Firehose event transformation. JSON normalization, schema validation, PII removal, partition key generation.
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
- **terraform/modules/security/** — WAF WebACL (Rate Limit + Bot Control), API Key management, IAM roles/policies.
- **terraform/modules/auth/** — Cognito User Pool + SSO IdP + Lambda@Edge authentication.
  - JWT validation at CloudFront viewer-request; redirects to Cognito Hosted UI when unauthenticated.
  - User identification via `x-user-sub` header; per-user conversation history isolation in AgentCore Memory.
- **lambda/edge-auth/** — CloudFront Lambda@Edge JWT verification function (Node.js 20). Token exchange, logout handling.

### Analysis Agent
- **agentcore/** — Bedrock AgentCore-based RUM analysis agent.
  - `agent.py` — Strands Agent (Claude Sonnet 4.6) + 8 tools. Runs inside AgentCore Runtime container.
  - `proxy.py` — Lightweight HTTP proxy on EC2. Calls AgentCore Runtime via boto3 `invoke-agent-runtime`, relays SSE stream.
  - `web-app/` — Next.js 14 Web UI. route.ts acts as SSE proxy to proxy.py (~46 lines).
- **AgentCore Managed Services:**
  - **Runtime** — Hosts agent.py container (ECR image, auto-scaling)
  - **Gateway** — Connects Athena Query Lambda via MCP protocol (`rum-athena-gw`)
  - **Memory** — Per-user conversation history (`rum_analysis_memory`, session_id=x-user-sub)
- **terraform/modules/agent-ui/** — Agent UI hosting infra (CloudFront + ALB + EC2 + proxy.py systemd)

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
│                     AI Analysis Agent (Agent UI → AgentCore)                     │
│                                                                                 │
│  ┌───────────┐   ┌─────────────┐   ┌─────────┐   ┌──────────────────────────┐  │
│  │ CloudFront│──▶│ Lambda@Edge │──▶│  ALB    │──▶│ EC2 (t4g.large)         │  │
│  │ (HTTPS)   │   │ (JWT Verify)│   │ (180s)  │   │                          │  │
│  └───────────┘   │ ┌─────────┐ │   │ SG:     │   │ Next.js :3000            │  │
│                  │ │ Cognito │ │   │ CF only │   │  └─ route.ts (SSE proxy) │  │
│                  │ │ SSO IdP │ │   └─────────┘   │       │                   │  │
│                  │ └─────────┘ │                  │       ▼                   │  │
│                  │ x-user-sub  │                  │ proxy.py :8080            │  │
│                  │ Header      │                  │  └─ boto3 invoke          │  │
│                  │ Injection   │                  │     -agent-runtime        │  │
│                  └─────────────┘                  └──────────┬───────────────┘  │
│                                                              │ SigV4            │
│  ┌───────────────────────────────────────────────────────────▼───────────────┐  │
│  │                    Bedrock AgentCore (Managed Services)                    │  │
│  │                                                                           │  │
│  │  ┌─────────────────────────────────────────────────────────────────────┐  │  │
│  │  │ Runtime (rumAnalysisAgent)                                          │  │  │
│  │  │  agent.py — Strands Agent (Claude Sonnet 4.6)                      │  │  │
│  │  │  ├─ StreamingHook → SSE events (status, chunk, done)               │  │  │
│  │  │  ├─ MemoryHook → auto save/load conversation history               │  │  │
│  │  │  └─ 8 tools (1 MCP Gateway + 7 boto3 direct)                      │  │  │
│  │  └─────────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                           │  │
│  │  ┌──────────────────────┐  ┌───────────────────────────────────────────┐  │  │
│  │  │ Memory               │  │ Gateway (rum-athena-gw)                   │  │  │
│  │  │ rum_analysis_memory  │  │  └─ Target: athena-query                  │  │  │
│  │  │ session_id =         │  │     └─ Lambda: rum-pipeline-athena-query  │  │  │
│  │  │   x-user-sub         │  │        MCP Tool: query_athena(sql)        │  │  │
│  │  │ (per-user isolation) │  │        → Athena SQL exec + result return  │  │  │
│  │  └──────────────────────┘  └───────────────────────────────────────────┘  │  │
│  └───────────────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────────────────────┐
│                          Infrastructure Management (IaC)                        │
│                                                                                 │
│  ┌──────────────────────────┐    ┌──────────────────────────┐                   │
│  │ Terraform (HCL)          │    │ CDK (TypeScript)          │                   │
│  │ 12 Modules:              │    │ 12 Constructs:            │                   │
│  │ s3-data-lake, glue,      │    │ S3DataLake, GlueCatalog,  │                   │
│  │ firehose, api-gateway,   │    │ Firehose, ApiGateway,     │                   │
│  │ security, monitoring,    │    │ Security, Monitoring,     │                   │
│  │ grafana, partition-repair│    │ Grafana, PartitionRepair, │                   │
│  │ athena-query, agent-ui,  │    │ AthenaQuery, AgentUi,     │                   │
│  │ auth, openreplay         │    │ Auth, OpenReplay          │                   │
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
```

## AI Analysis Request Flow (User → AgentCore)

```
User (Browser)
  │ POST /api/chat { prompt: "Show today's RUM status" }
  ▼
CloudFront (HTTPS) → Lambda@Edge (JWT verify, inject x-user-sub) → ALB (idle 180s)
  │
  ▼
EC2 Next.js route.ts :3000 (SSE proxy, ~46 lines)
  │ fetch("http://localhost:8080/invocations", { prompt, session_id: x-user-sub })
  ▼
EC2 proxy.py :8080 (systemd: rum-agent.service)
  │ boto3.client("bedrock-agentcore").invoke_agent_runtime(
  │     agentRuntimeArn=".../rumAnalysisAgent-...",
  │     qualifier="rumAgentEndpoint",
  │     payload=b'{"prompt":"...","session_id":"..."}'
  │ )
  │ → resp["response"].iter_chunks() → SSE relay
  ▼
AgentCore Runtime (managed, container: rum-agent:latest)
  │ @app.entrypoint async def invoke()
  │   ① MemoryHook: Load last 5 turns from AgentCore Memory (session_id=x-user-sub)
  │   ② StreamingHook: Push tool execution status as SSE events
  │   ③ Connect MCP Gateway (SigV4, discover Athena Query Lambda tool)
  ▼
Strands Agent (Claude Sonnet 4.6, Bedrock Converse API, native tool_use)
  │
  ├── [MCP Gateway] query_athena(sql)
  │     → rum-athena-gw → Lambda:rum-pipeline-athena-query → Athena
  │     → SQL: SELECT ... FROM rum_pipeline_db.rum_events WHERE year/month/day
  │
  ├── [boto3 direct] search_logs(log_group, pattern)    → CloudWatch Logs
  ├── [boto3 direct] get_metrics(namespace, metric)     → CloudWatch Metrics
  ├── [boto3 direct] describe_alarms(state)             → CloudWatch Alarms
  ├── [boto3 direct] select_s3_object(key, expression)  → S3 Select
  ├── [boto3 direct] get_table_schema(table)            → Glue Catalog
  ├── [boto3 direct] create_grafana_annotation(text)    → Grafana API
  └── [boto3 direct] publish_sns(message)               → SNS Publish
  │
  ▼
SSE Response Stream (reverse path)
  agent.py yield → AgentCore Runtime → proxy.py iter_chunks → route.ts passthrough → Browser
    {"type": "start"}
    {"type": "status", "content": "Athena analyzing..."}
    {"type": "status", "content": "✅ Athena complete"}
    {"type": "heartbeat"}                                   ← every 15s
    {"type": "chunk", "content": "## Today's RUM Status..."} ← markdown report
    {"type": "done"}
```

### AgentCore Gateway Configuration

```
rum-athena-gw (MCP protocol, IAM auth)
  └── Target: athena-query (READY)
        ├── Lambda: rum-pipeline-athena-query
        │   (async Athena query: execute → poll → return results)
        └── MCP Tool: query_athena
              ├── Input: { "sql": "SELECT ... FROM rum_pipeline_db.rum_events WHERE ..." }
              ├── Constraint: SELECT only, year/month/day partition filter required
              └── Forbidden funcs: COUNTIF→COUNT_IF, SAFE_DIVIDE→TRY, IFNULL→COALESCE
```

### Per-User Isolation

```
User A (Cognito sub: "aaa") → Lambda@Edge x-user-sub: "aaa"
  → proxy.py session_id: "aaa" → AgentCore Memory: loads/saves only User A's history

User B (Cognito sub: "bbb") → Lambda@Edge x-user-sub: "bbb"
  → proxy.py session_id: "bbb" → AgentCore Memory: loads/saves only User B's history
```

## Infrastructure

### AWS Region
- ap-northeast-2 (Seoul)

### Terraform Modules (terraform/modules/)
| Module | Resources | Description |
|--------|-----------|-------------|
| s3-data-lake | S3 Bucket | Single bucket (raw/, aggregated/, athena-results/, errors/ prefixes) |
| glue-catalog | Glue DB + 3 Tables | rum_events, rum_hourly_metrics, rum_daily_summary |
| firehose | Kinesis Firehose | Dynamic partitioning + Parquet conversion, Transform Lambda |
| api-gateway | HTTP API, Lambda Integration | POST /v1/events, /v1/events/beacon |
| security | WAF, API Key, IAM | Authentication/authorization infrastructure |
| monitoring | CloudWatch | Dashboards, alarms |
| grafana | AMG Workspace | Athena data source |
| partition-repair | Lambda, EventBridge | Automatic partition repair |
| athena-query | Lambda | Query execution API |
| agent-ui | CloudFront + ALB + EC2 | AgentCore Web UI hosting |
| auth | Cognito, Lambda@Edge | SSO authentication + JWT validation |
| openreplay | CloudFront, ALB, EC2, RDS, ElastiCache, S3 | Session replay (self-hosted OpenReplay) |

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
| OpenReplay | openreplay | Session replay (CF + ALB + EC2 + RDS + Redis + S3) |

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
- Self-hosted OpenReplay for session replay data sovereignty (cost savings vs SaaS, RDS+Redis+S3 as external managed services)
- Agent UI ALB idle_timeout 180s + SSE heartbeat (15s interval) to prevent multi-round AI analysis timeouts
- Athena/Trino forbidden function list (COUNTIF, SAFE_DIVIDE, IFNULL, IF, GROUP_CONCAT) ensures SQL compatibility
- Agent tool call limit (max 2 per round) prevents unnecessary API calls and optimizes cost
- Agent UI PDF/Word report download implemented via DOM cloning without server-side rendering
- EC2 proxy.py → AgentCore Runtime invoke API for agent calls (route.ts is SSE proxy only, eliminates code duplication)
- MCP Gateway connects only Athena; remaining 7 tools use boto3 direct calls (only async queries need Lambda encapsulation)
- AgentCore Runtime container deployment with ECR image versioning for zero-downtime updates

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
