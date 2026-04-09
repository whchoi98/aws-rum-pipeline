# Changelog

[![English](https://img.shields.io/badge/lang-English-blue.svg)](#english) [![한국어](https://img.shields.io/badge/lang-한국어-red.svg)](#한국어)

---

# English

All notable changes to this project will be documented in this file.
The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- AgentCore Runtime integration: proxy.py HTTP proxy on EC2 calls AgentCore Runtime via boto3 `invoke-agent-runtime`, SSE streaming relay
- `proxy.py` lightweight HTTP proxy (Starlette/uvicorn, port 8080) replaces direct Bedrock InvokeModel in route.ts
- `rum-agent.service` systemd service for proxy.py on EC2
- `StreamingHook` (Strands HookProvider) for real-time tool execution status events (BeforeToolCallEvent/AfterToolCallEvent)
- `run_agent()` function with MCP context manager wrapping to fix MCPClientInitializationError
- End-to-end data flow diagram in architecture.md (SDK → Ingestion → Storage → Grafana/CW/AI Agent)
- AI analysis request flow diagram (User → CloudFront → EC2 → AgentCore Runtime → Strands Agent → 8 tools)
- AgentCore Gateway configuration details (rum-athena-gw, MCP Tool, forbidden functions)
- Three analysis paths comparison table (Grafana vs CloudWatch vs AI Agent)
- Per-user isolation flow diagram (x-user-sub → session_id → AgentCore Memory)

### Changed

- `route.ts` reduced from 313 lines to 46 lines (SSE proxy to localhost:8080, removed Bedrock direct calls)
- `agent.py` entrypoint converted from sync return to async streaming generator with heartbeat (15s)
- `agent.py` `create_agent()` refactored to `run_agent()` — creates + executes agent inside MCP context manager
- Removed 6 AWS SDK packages from web-app: @aws-sdk/client-lambda, bedrock-runtime, cloudwatch-logs, cloudwatch, glue, sns
- Agent UI architecture: tag-based XML orchestration replaced with Strands native tool_use via AgentCore Runtime
- AgentCore Runtime container updated to v3 (ECR image rebuild with streaming + MCP fix)
- Terraform agent-ui user_data: added pip3 install + rum-agent systemd service registration

### Removed

- Agent UI direct Bedrock InvokeModel calls (replaced by AgentCore Runtime invoke)
- Agent UI 7 tool functions in route.ts (queryAthena, searchLogs, getMetrics, etc.)
- Agent UI XML tag parsing (extractToolTags, runTool, stripTags)
- Agent UI SYSTEM_PROMPT duplicate in route.ts (single source in agent.py)

---

- OpenReplay self-hosted session replay module: CloudFront + ALB + EC2 + RDS (PostgreSQL) + ElastiCache (Redis) + S3
- CDK `OpenReplay` Construct with 1:1 mapping to Terraform openreplay module
- TAP-style harness validation test suite (`tests/run-all.sh`) with 108 tests covering hooks, structure, secret patterns, and content quality
- ADR-007: OpenReplay session replay architecture decision
- Runbook 14: OpenReplay management and operations
- Agent YAML system prompts with structured output formats (code-reviewer, security-auditor)
- Error recovery sections for all 3 commands and 4 skills
- Claude Code harness section in onboarding documentation (KR/EN)
- SSE heartbeat (15s interval) in Agent UI chat route for long-running AI analysis
- AgentCore 7 analysis tools: CloudWatch Logs/Metrics/Alarms, S3 Select, Glue Catalog, Grafana API, SNS Publish
- Agent UI tag-based multi-tool system (`<SQL>`, `<CWLOGS>`, `<METRICS>`, `<ALARM>`, `<GLUE>`, `<GRAFANA>`, `<SNS>`)
- Agent UI header: "Powered by Amazon Bedrock AgentCore" + Agentic AI badge + Claude Sonnet 4.6
- Agent UI download menu: rendered PDF/Word with status message filtering + Markdown export
- EC2 IAM role: CloudWatch, Glue, SNS, Lambda invoke permissions for analysis tools
- Athena/Trino SQL rules: forbidden function mapping (COUNTIF→COUNT_IF, IFNULL→COALESCE, etc.)
- Tool call rate limiting: max 2 tools per round to prevent slow responses

### Fixed

- Claude Code settings: replaced invalid `PreCommit` hook key with `PreToolUse` matcher for Bash `git commit` commands
- OpenReplay EC2 switched to x86_64 — Docker images are amd64 only
- OpenReplay JWT secret added to Terraform, simplified user_data SSM reads
- Agent UI SSE timeout: ALB idle_timeout 180s + CloudFront origin_keepalive_timeout 60s
- Agent UI 401 Unauthorized: fallback to anonymous when Lambda@Edge (SSO) is not attached
- Agent UI SSE client parsing: buffer-based event parsing to handle CloudFront response buffering

### Security

- Secret scanner upgraded from advisory (exit 0) to blocking gate (exit 1 on detection)
- Secret patterns expanded from 6 to 10 (added AWS secret key, private key, JWT, Slack webhook/token)
- Write/Edit PreToolUse hook added for secret scanning on file creation/modification
- Deny list expanded from 8 to 18 rules (added git clean, git checkout/restore, eval, chmod 777, terraform apply -auto-approve)
- Grafana API key scrubbed from settings.local.json allow rules

## [0.5.0] - 2026-04-04

### Added

- Cognito User Pool + SSO Identity Provider integration for Agent UI authentication
- Lambda@Edge (viewer-request) JWT validation with JWKS verification and cookie-based sessions
- Per-user AgentCore Memory isolation using Cognito `sub` claim as `session_id`
- Terraform `auth` module (Cognito, App Client, SSO IdP, Lambda@Edge in us-east-1)
- CDK `Auth` construct with `EdgeFunction` for cross-region Lambda@Edge deployment
- Cognito SSO setup and management runbook

### Changed

- Agent UI CloudFront distribution now supports Lambda@Edge association (dynamic block)
- Chat route (`/api/chat`) requires `x-user-sub` header, returns 401 if missing
- Terraform providers updated to include `us-east-1` alias for Lambda@Edge

### Security

- Agent UI access restricted to authenticated SSO users only
- JWT tokens stored as HttpOnly + Secure + SameSite=Lax cookies
- PKCE enabled for Authorization Code flow to prevent code interception

## [0.4.0] - 2026-04-04

### Added

- Premium Grafana admin dashboard with 43 panels across 9 sections (KPI, Traffic Trends, Core Web Vitals, Errors & Crashes, Resources & Network, Mobile Vitals, User Analysis, Page Performance, Session Explorer)
- AWS CDK (TypeScript) project with 11 constructs mapping 1:1 to Terraform modules
- Shared CDK helpers (`createPipelineLambda`, `glueReadPolicy`, `athenaExecPolicy`, `parquetStorageDescriptor`)
- ADR-001: Dual IaC (Terraform + CDK) decision
- 8 operational runbooks (deployment, API key rotation, pipeline failure, Grafana management, E2E testing, EKS simulator, monitoring, AgentCore setup)
- `terraform.tfvars.example` for safe configuration templating

### Changed

- CloudFront viewer protocol policy changed from `allow-all` to `redirect-to-https`
- Terraform VPC/Subnet/AgentCore ARN moved from hardcoded values to variables
- `provision-grafana.sh` now requires `ACCOUNT_ID` as mandatory input
- Bedrock IAM policy scoped to `anthropic.*` foundation models instead of wildcard

### Fixed

- Partition Repair Lambda failing due to missing `glue:GetDatabase` IAM permission
- Glue table schema mismatch between CDK and Terraform (`period_start`, `avg_session_duration_sec`)
- Firehose delivery stream name inconsistency between CDK and Terraform

### Security

- All sensitive data removed from source code (AWS account IDs, VPC IDs, API Gateway URLs, Grafana workspace URLs, SSO portal URLs, CloudFront distribution IDs)
- `.gitignore` updated to exclude `terraform.tfvars`, `.env`, `*.local.json`, `cdk.out/`
- S3 bucket versioning now includes noncurrent version expiration (30 days)

## [0.3.0] - 2026-04-03

### Added

- Bedrock AgentCore RUM analysis agent with Strands Agent + MCP tool integration
- Next.js 14 chat UI with SSE streaming and 3-round SQL execution loop
- AgentCore infrastructure: CloudFront + ALB + EC2 (t4g.large) for Agent UI hosting
- AgentCore Memory integration for conversation history persistence
- Chat route with `<SQL>` tag-based auto-execution workflow
- iOS RUM SDK (Swift 5.9+, SPM) with crash, screen, performance, and action collectors
- Android RUM SDK (Kotlin 1.9+, Gradle) with crash, ANR, screen, performance, and action collectors
- Unified setup script (`scripts/setup.sh`) with 6 installation phases

### Fixed

- CloudFront prefix list security group rule for ALB access restriction
- Root object redirect loop in CloudFront distribution

## [0.2.0] - 2026-04-02

### Added

- TypeScript RUM SDK with Core Web Vitals (LCP/CLS/INP), error, navigation, and resource collectors
- EventBuffer with batch size, timer flush, and overflow cap
- Transport with fetch, exponential backoff retry, and sendBeacon fallback
- RUM traffic simulator with Web (60%), iOS (25%), Android (15%) distribution and 3 scenarios
- Amazon Managed Grafana workspace with Athena data source
- Athena workgroup with 100GB scan limit and CloudWatch metrics
- Core Web Vitals, Error Monitoring, and Traffic Overview Grafana dashboard JSONs
- Grafana provisioning script for automated data source and dashboard setup
- Partition Repair Lambda with EventBridge schedule (every 15 minutes)
- CloudWatch dashboard with Korean labels, 22 widgets across 8 rows
- Simulator Docker image and EKS CronJob configuration
- iOS and Android platform support in simulator

### Changed

- CloudWatch dashboard upgraded with additional Lambda and Firehose metrics

## [0.1.0] - 2026-04-01

### Added

- S3 Data Lake module with lifecycle policies (raw 90 days, aggregated tiering, errors 30 days)
- Glue Catalog module with `rum_events`, `rum_hourly_metrics`, and `rum_daily_summary` tables
- Kinesis Data Firehose module with Lambda transform, Parquet conversion, and dynamic partitioning
- Transform Lambda with schema validation, PII stripping, and partition key extraction
- Ingest Lambda for HTTP to Firehose bridging
- API Gateway HTTP API module with Lambda integration
- Lambda Authorizer with SSM Parameter Store-backed API key validation
- Security module with WAF WebACL (rate limiting + bot control)
- Root Terraform module wiring all submodules with dependency chain
- End-to-end integration test script (`test-ingestion.sh`)
- S3 remote state backend with DynamoDB lock table

### Fixed

- API Gateway conditional resource count using plan-time known boolean
- Deployment issues found during initial `terraform apply`

[Unreleased]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/whchoi98/aws-rum-pipeline/releases/tag/v0.1.0

---

# 한국어

이 프로젝트의 모든 주요 변경 사항은 이 파일에 기록됩니다.
이 문서는 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)를 기반으로 하며,
[Semantic Versioning](https://semver.org/spec/v2.0.0.html)을 따릅니다.

## [Unreleased]

### Added

- AgentCore Runtime 통합: EC2 proxy.py HTTP 프록시가 boto3 `invoke-agent-runtime`으로 AgentCore Runtime 호출, SSE 스트리밍 중계
- `proxy.py` 경량 HTTP 프록시 (Starlette/uvicorn, port 8080) — route.ts의 Bedrock InvokeModel 직접 호출 대체
- `rum-agent.service` systemd 서비스로 proxy.py EC2 상시 실행
- `StreamingHook` (Strands HookProvider) — BeforeToolCallEvent/AfterToolCallEvent로 도구 실행 상태 실시간 전달
- `run_agent()` 함수 + MCP 컨텍스트 매니저 래핑으로 MCPClientInitializationError 해결
- architecture.md에 End-to-End 데이터 플로우 다이어그램 (SDK → 인제스트 → 저장 → Grafana/CW/AI Agent)
- AI 분석 요청 흐름 다이어그램 (사용자 → CloudFront → EC2 → AgentCore Runtime → Strands Agent → 8개 도구)
- AgentCore Gateway 구성 상세 (rum-athena-gw, MCP Tool, 금지 함수)
- 세 분석 경로 비교표 (Grafana vs CloudWatch vs AI Agent)
- 사용자별 격리 흐름 다이어그램 (x-user-sub → session_id → AgentCore Memory)

### Changed

- `route.ts` 313줄 → 46줄로 축소 (localhost:8080 SSE 프록시, Bedrock 직접 호출 제거)
- `agent.py` entrypoint를 동기 반환에서 비동기 스트리밍 generator로 변환 (heartbeat 15초)
- `agent.py` `create_agent()` → `run_agent()`으로 리팩터 — MCP 컨텍스트 매니저 안에서 에이전트 생성+실행
- web-app에서 AWS SDK 6개 패키지 제거: @aws-sdk/client-lambda, bedrock-runtime, cloudwatch-logs, cloudwatch, glue, sns
- Agent UI 아키텍처: XML 태그 기반 오케스트레이션 → AgentCore Runtime 경유 Strands 네이티브 tool_use로 전환
- AgentCore Runtime 컨테이너 v3 업데이트 (ECR 이미지 재빌드: 스트리밍 + MCP 수정 반영)
- Terraform agent-ui user_data: pip3 설치 + rum-agent systemd 서비스 등록 추가

### Removed

- Agent UI의 Bedrock InvokeModel 직접 호출 (AgentCore Runtime invoke로 대체)
- route.ts의 7개 도구 함수 (queryAthena, searchLogs, getMetrics 등)
- route.ts의 XML 태그 파싱 (extractToolTags, runTool, stripTags)
- route.ts의 SYSTEM_PROMPT 중복 (agent.py에서 단일 관리)

---

- OpenReplay 셀프호스팅 세션 리플레이 모듈: CloudFront + ALB + EC2 + RDS (PostgreSQL) + ElastiCache (Redis) + S3
- Terraform openreplay 모듈과 1:1 대응하는 CDK `OpenReplay` Construct
- TAP 스타일 하네스 검증 테스트 스위트 (`tests/run-all.sh`) — 훅, 구조, 시크릿 패턴, 콘텐츠 품질 108개 테스트
- ADR-007: OpenReplay 세션 리플레이 아키텍처 결정
- 런북 14: OpenReplay 관리 및 운영
- 에이전트 YAML 시스템 프롬프트 + 구조화된 출력 형식 (code-reviewer, security-auditor)
- 3개 명령 + 4개 스킬에 에러 복구 섹션 추가
- 온보딩 문서에 Claude Code 하네스 섹션 추가 (KR/EN)
- Agent UI 채팅 라우트에 SSE heartbeat (15초 간격) 추가
- AgentCore 7개 분석 도구: CloudWatch Logs/Metrics/Alarms, S3 Select, Glue Catalog, Grafana API, SNS Publish
- Agent UI 태그 기반 멀티 도구 시스템 (`<SQL>`, `<CWLOGS>`, `<METRICS>`, `<ALARM>`, `<GLUE>`, `<GRAFANA>`, `<SNS>`)
- Agent UI 헤더: "Powered by Amazon Bedrock AgentCore" + Agentic AI 배지 + Claude Sonnet 4.6
- Agent UI 다운로드 메뉴: 렌더링 PDF/Word (상태 메시지 필터링) + Markdown 내보내기
- EC2 IAM 역할: CloudWatch, Glue, SNS, Lambda 호출 권한 추가
- Athena/Trino SQL 규칙: 금지 함수 매핑 (COUNTIF→COUNT_IF, IFNULL→COALESCE 등)
- 도구 호출 제한: 라운드당 최대 2개로 응답 속도 개선

### Fixed

- Claude Code 설정: 잘못된 `PreCommit` 훅 키를 Bash `git commit` 매칭 `PreToolUse`로 교체
- OpenReplay EC2를 x86_64로 전환 — Docker 이미지가 amd64 전용
- OpenReplay Terraform에 JWT 시크릿 추가, user_data SSM 읽기 간소화
- Agent UI SSE 타임아웃: ALB idle_timeout 180초 + CloudFront origin_keepalive_timeout 60초
- Agent UI 401 Unauthorized: Lambda@Edge (SSO) 미연결 시 anonymous fallback
- Agent UI SSE 클라이언트 파싱: CloudFront 응답 버퍼링 대응 버퍼 기반 이벤트 파싱

### Security

- 시크릿 스캐너를 권고(exit 0)에서 차단 게이트(exit 1)로 업그레이드
- 시크릿 패턴 6개 → 10개 확장 (AWS 시크릿 키, 개인키, JWT, Slack 웹훅/토큰 추가)
- Write/Edit PreToolUse 훅 추가 — 파일 생성/수정 시 시크릿 스캔
- deny 리스트 8개 → 18개 확장 (git clean, git checkout/restore, eval, chmod 777, terraform apply -auto-approve)
- settings.local.json에서 Grafana API 키 평문 제거

## [0.5.0] - 2026-04-04

### Added

- Agent UI 인증을 위한 Cognito User Pool + SSO Identity Provider 연동
- Lambda@Edge (viewer-request) JWT 검증 (JWKS 검증 및 쿠키 기반 세션)
- Cognito `sub` 클레임을 `session_id`로 사용한 사용자별 AgentCore Memory 분리
- Terraform `auth` 모듈 (Cognito, App Client, SSO IdP, us-east-1 Lambda@Edge)
- CDK `Auth` Construct (`EdgeFunction`으로 크로스 리전 Lambda@Edge 배포)
- Cognito SSO 설정 및 관리 런북

### Changed

- Agent UI CloudFront 배포에 Lambda@Edge association 지원 (dynamic block)
- 채팅 라우트(`/api/chat`)가 `x-user-sub` 헤더 필수, 미포함 시 401 반환
- Terraform provider에 Lambda@Edge용 `us-east-1` alias 추가

### Security

- Agent UI 접근을 인증된 SSO 사용자로 제한
- JWT 토큰을 HttpOnly + Secure + SameSite=Lax 쿠키로 저장
- Authorization Code 플로우에 PKCE 활성화로 코드 탈취 방지

## [0.4.0] - 2026-04-04

### Added

- 9개 섹션 43개 패널의 프리미엄 Grafana 관리자 대시보드 (KPI, 트래픽 추이, Core Web Vitals, 에러 & 크래시, 리소스 & 네트워크, 모바일 바이탈, 사용자 분석, 페이지별 성능, 세션 탐색기)
- Terraform 11개 모듈과 1:1 대응하는 AWS CDK (TypeScript) 프로젝트 11개 Construct
- CDK 공유 헬퍼 (`createPipelineLambda`, `glueReadPolicy`, `athenaExecPolicy`, `parquetStorageDescriptor`)
- ADR-001: 듀얼 IaC (Terraform + CDK) 결정 문서
- 운영 런북 8개 (배포, API Key 로테이션, 파이프라인 장애, Grafana 관리, E2E 테스트, EKS 시뮬레이터, 모니터링, AgentCore 셋업)
- 안전한 설정 템플릿 `terraform.tfvars.example`

### Changed

- CloudFront viewer protocol policy를 `allow-all`에서 `redirect-to-https`로 변경
- Terraform VPC/Subnet/AgentCore ARN을 하드코딩에서 변수로 분리
- `provision-grafana.sh`에서 `ACCOUNT_ID`를 필수 입력으로 변경
- Bedrock IAM 정책을 와일드카드 대신 `anthropic.*` 파운데이션 모델로 범위 축소

### Fixed

- Partition Repair Lambda의 `glue:GetDatabase` IAM 권한 누락으로 인한 실패 수정
- CDK와 Terraform 간 Glue 테이블 스키마 불일치 수정 (`period_start`, `avg_session_duration_sec`)
- CDK와 Terraform 간 Firehose delivery stream 이름 불일치 수정

### Security

- 소스 코드에서 모든 민감 데이터 제거 (AWS 계정 ID, VPC ID, API Gateway URL, Grafana URL, SSO 포털 URL, CloudFront 배포 ID)
- `.gitignore`에 `terraform.tfvars`, `.env`, `*.local.json`, `cdk.out/` 추가
- S3 버킷 버전 관리에 비현재 버전 만료 (30일) 추가

## [0.3.0] - 2026-04-03

### Added

- Bedrock AgentCore RUM 분석 에이전트 (Strands Agent + MCP 도구 연동)
- SSE 스트리밍 및 3라운드 SQL 자동 실행 루프가 포함된 Next.js 14 채팅 UI
- AgentCore 인프라: CloudFront + ALB + EC2 (t4g.large) Agent UI 호스팅
- 대화 히스토리 유지를 위한 AgentCore Memory 연동
- `<SQL>` 태그 기반 자동 실행 워크플로우 적용된 채팅 라우트
- iOS RUM SDK (Swift 5.9+, SPM) — 크래시, 화면, 성능, 액션 수집기
- Android RUM SDK (Kotlin 1.9+, Gradle) — 크래시, ANR, 화면, 성능, 액션 수집기
- 6단계 설치 Phase가 포함된 통합 설치 스크립트 (`scripts/setup.sh`)

### Fixed

- ALB 접근 제한을 위한 CloudFront prefix list 보안 그룹 규칙 수정
- CloudFront 배포의 루트 오브젝트 리다이렉트 루프 수정

## [0.2.0] - 2026-04-02

### Added

- Core Web Vitals (LCP/CLS/INP), 에러, 네비게이션, 리소스 수집기가 포함된 TypeScript RUM SDK
- 배치 크기, 타이머 플러시, 오버플로우 캡이 적용된 EventBuffer
- fetch, 지수 백오프 재시도, sendBeacon 폴백이 포함된 Transport
- Web (60%), iOS (25%), Android (15%) 분포 및 3가지 시나리오의 RUM 트래픽 시뮬레이터
- Athena 데이터소스가 연결된 Amazon Managed Grafana 워크스페이스
- 100GB 스캔 제한 및 CloudWatch 메트릭이 적용된 Athena 워크그룹
- Core Web Vitals, Error Monitoring, Traffic Overview Grafana 대시보드 JSON
- 자동 데이터소스 및 대시보드 설정을 위한 Grafana 프로비저닝 스크립트
- EventBridge 스케줄 (15분 간격)로 실행되는 Partition Repair Lambda
- 한글 라벨, 22개 위젯, 8개 Row의 CloudWatch 대시보드
- 시뮬레이터 Docker 이미지 및 EKS CronJob 설정
- 시뮬레이터의 iOS 및 Android 플랫폼 지원

### Changed

- CloudWatch 대시보드에 Lambda 및 Firehose 추가 메트릭 반영

## [0.1.0] - 2026-04-01

### Added

- 라이프사이클 정책이 적용된 S3 Data Lake 모듈 (raw 90일, aggregated 계층화, errors 30일)
- `rum_events`, `rum_hourly_metrics`, `rum_daily_summary` 테이블이 정의된 Glue Catalog 모듈
- Lambda Transform, Parquet 변환, 동적 파티셔닝이 포함된 Kinesis Data Firehose 모듈
- 스키마 검증, PII 제거, 파티션 키 추출이 포함된 Transform Lambda
- HTTP → Firehose 브리지 Ingest Lambda
- Lambda 연동이 포함된 API Gateway HTTP API 모듈
- SSM Parameter Store 기반 API Key 검증 Lambda Authorizer
- WAF WebACL (Rate Limit + Bot Control)이 포함된 Security 모듈
- 모든 서브모듈을 의존성 체인으로 연결하는 루트 Terraform 모듈
- 엔드투엔드 통합 테스트 스크립트 (`test-ingestion.sh`)
- DynamoDB 잠금 테이블이 포함된 S3 원격 상태 백엔드

### Fixed

- plan-time 확인 가능한 boolean을 사용한 API Gateway 조건부 리소스 count 수정
- 최초 `terraform apply` 중 발견된 배포 이슈 수정

[Unreleased]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.5.0...HEAD
[0.5.0]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.4.0...v0.5.0
[0.4.0]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.3.0...v0.4.0
[0.3.0]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/whchoi98/aws-rum-pipeline/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/whchoi98/aws-rum-pipeline/releases/tag/v0.1.0
