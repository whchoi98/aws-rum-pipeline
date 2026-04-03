# Architecture

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

### Analysis Agent
- **agentcore/** — Bedrock AgentCore 기반 RUM 분석 에이전트.
  - `agent.py` — Strands Agent + MCP 도구 연결. Athena 쿼리, 이상 감지, 리포트 생성.
  - `web/` — Next.js 14 Web UI (에이전트 채팅 인터페이스).
  - `web-app/` — 별도 배포 가능한 Next.js 앱.
- **terraform/modules/agent-ui/** — AgentCore UI 호스팅 인프라.

### Traffic Simulation
- **simulator/** — TypeScript 트래픽 생성기. 실제 브라우저 SDK 호출 시뮬레이션. Docker 컨테이너화.

## Data Flow

```
Browser
  └─(SDK)─→ API Gateway (/ingest)
              └─(Lambda Authorizer: 인증)─→ ingest Lambda
                                              └─→ Kinesis Firehose
                                                    └─(transform Lambda)─→ S3 (raw/)
                                                                             └─(partition-repair)─→ Glue Catalog
                                                                                                     └─→ Athena
                                                                                                           └─→ Grafana / AgentCore Web UI
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
| agent-ui | ECS/EKS or CloudFront | AgentCore Web UI 호스팅 |

### Deployed Resources (ap-northeast-2)
- API Endpoint: `https://<api-id>.execute-api.ap-northeast-2.amazonaws.com`
- Grafana: `https://<workspace-id>.grafana-workspace.ap-northeast-2.amazonaws.com`
- SSM Parameter: `/rum-pipeline/dev/api-keys`

## Key Design Decisions

- Firehose를 중간 버퍼로 사용해 Lambda throttling 없이 고처리량 지원
- Lambda Authorizer로 API Key 검증을 Gateway 레벨에서 처리
- Glue 파티션을 날짜 기준으로 구성해 Athena 쿼리 비용 최소화
- Bedrock AgentCore로 에이전트 인프라 관리 부담 제거
