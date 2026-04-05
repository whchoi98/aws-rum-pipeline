<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Project Context

### Overview

AWS Custom RUM Pipeline — AWS 서버리스 기반 Real User Monitoring 솔루션.
브라우저 SDK로 수집한 RUM 이벤트를 API Gateway → Lambda → Firehose → S3 경로로 처리하고,
Glue/Athena로 쿼리 가능하게 만드는 서버리스 파이프라인.
Bedrock AgentCore 기반 분석 에이전트 포함.

### Tech Stack

- **Infrastructure**: Terraform (HCL) + AWS CDK (TypeScript), AWS provider
- **Lambda**: Python 3.12, pytest
- **SDK**: TypeScript, esbuild, vitest
- **Mobile SDK (iOS)**: Swift 5.9+, Swift Package Manager
- **Mobile SDK (Android)**: Kotlin 1.9+, Gradle
- **Simulator**: TypeScript, Docker
- **Agent UI**: TypeScript, Next.js 14, Docker
- **AgentCore**: Python 3.12, Bedrock AgentCore

### Project Structure

```
terraform/          - Terraform 루트 모듈 + 11개 서브모듈
  modules/
    s3-data-lake/   - S3 버킷 (raw/processed/athena-results)
    glue-catalog/   - Glue 데이터베이스 및 테이블 스키마
    firehose/       - Kinesis Data Firehose (S3 delivery)
    api-gateway/    - HTTP API + ingest Lambda 연결
    security/       - WAF, API Key, Lambda Authorizer
    monitoring/     - CloudWatch 대시보드 및 알람
    grafana/        - Amazon Managed Grafana 워크스페이스
    partition-repair/ - Glue 파티션 자동 복구 Lambda
    athena-query/   - Athena 쿼리 결과 조회 Lambda
    agent-ui/       - AgentCore UI 호스팅 인프라
    auth/           - Cognito SSO + Lambda@Edge 인증
lambda/             - Python Lambda 함수
  authorizer/       - JWT/API Key 검증 Lambda Authorizer
  ingest/           - HTTP → Firehose 브리지
  transform/        - Firehose 이벤트 변환 (JSON 정규화)
  partition-repair/ - Glue 파티션 MSCK REPAIR
  athena-query/     - Athena 쿼리 실행 및 결과 반환
  edge-auth/        - CloudFront Lambda@Edge JWT 검증 (Node.js)
sdk/                - TypeScript RUM SDK (브라우저 클라이언트)
mobile-sdk-ios/     - iOS RUM SDK (Swift, SPM)
mobile-sdk-android/ - Android RUM SDK (Kotlin, Gradle)
simulator/          - RUM 트래픽 생성기 (Docker)
agentcore/          - Bedrock AgentCore RUM 분석 에이전트 + Web UI
  agent.py          - 에이전트 메인 (Strands, MCP)
  web/              - Next.js 14 Web UI
  web-app/          - 별도 Next.js 앱 (필요시)
cdk/                - AWS CDK (TypeScript) — Terraform과 동일 인프라
  lib/constructs/   - 11개 Construct (Terraform 모듈과 1:1 대응, auth 포함)
  lib/rum-pipeline-stack.ts - 메인 스택
scripts/            - 빌드/배포/테스트 쉘 스크립트
docs/               - 아키텍처 문서, ADR, 런북
.claude/            - Claude Code 설정 (hooks, skills)
.kiro/              - Kiro 에이전트 설정
tools/              - 프롬프트, 유틸리티 스크립트
CHANGELOG.md        - 릴리스 변경 이력 (Keep a Changelog)
```

### Key Commands

```bash
# Terraform
cd terraform && terraform fmt -recursive
cd terraform && terraform plan
cd terraform && terraform apply

# Lambda 테스트 (각 함수별)
cd lambda/authorizer && python3 -m pytest test_handler.py -v
cd lambda/ingest && python3 -m pytest test_handler.py -v
cd lambda/transform && python3 -m pytest test_handler.py -v
cd lambda/partition-repair && python3 -m pytest test_handler.py -v
cd lambda/athena-query && python3 -m pytest test_handler.py -v

# SDK 테스트
cd sdk && npm test           # vitest
cd sdk && npm run build      # esbuild

# iOS SDK
cd mobile-sdk-ios && swift build
cd mobile-sdk-ios && swift test

# Android SDK
cd mobile-sdk-android && ./gradlew :rum-sdk:build
cd mobile-sdk-android && ./gradlew :rum-sdk:test

# Simulator
cd simulator && npm test
cd simulator && docker build -t rum-simulator .

# CDK
cd cdk && npm install
cd cdk && npx cdk synth         # CloudFormation 생성
cd cdk && npx cdk deploy        # 배포

# AgentCore
cd agentcore && python3 agent.py

# 전체 설치
./scripts/setup.sh all

# 통합 테스트
bash scripts/test-ingestion.sh "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com"
```

### Conventions

- **주석**: 한국어 우선 (Korean comments preferred)
- **Terraform**: `terraform fmt` 필수, 모듈별 독립 관리
- **Python**: Black 포맷터, type hints 권장, pytest 테스트
- **TypeScript**: ESM, strict 타입, vitest 테스트
- **환경 분리**: `dev` / `prod` workspace 또는 tfvars
- **모노레포**: 각 패키지 독립 (node_modules, requirements.txt 분리)
- **시크릿**: AWS SSM Parameter Store 사용, 하드코딩 금지
- **리전**: ap-northeast-2 (서울) 기본

---

### Auto-Sync Rules

Rules below are applied automatically after Plan mode exit and on major code changes.

#### Post-Plan Mode Actions
After exiting Plan mode (`/plan`), before starting implementation:

1. **Architecture decision made** -> Update `docs/architecture.md`
2. **Technical choice/trade-off made** -> Create `docs/decisions/ADR-NNN-title.md`
3. **New module added** -> Create `CLAUDE.md` in that module directory
4. **Operational procedure defined** -> Create runbook in `docs/runbooks/`
5. **Changes needed in this file** -> Update relevant sections above

#### Code Change Sync Rules
- New directory under `terraform/modules/` -> Must create `CLAUDE.md` alongside
- New Lambda function added -> Update `lambda/CLAUDE.md`
- API endpoint added/changed -> Update `terraform/modules/api-gateway/` CLAUDE.md
- Infrastructure changed -> Update `docs/architecture.md` Infrastructure section
- New ADR created -> Number sequentially (find max in `docs/decisions/ADR-*.md`)

#### ADR Numbering
Find the highest number in `docs/decisions/ADR-*.md` and increment by 1.
Format: `ADR-NNN-concise-title.md`

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Project Context

### Overview

AWS Custom RUM Pipeline — A serverless Real User Monitoring solution built on AWS.
Collects RUM events via a browser SDK and processes them through the API Gateway → Lambda → Firehose → S3 path,
making them queryable with Glue/Athena as a serverless pipeline.
Includes an analytics agent powered by Bedrock AgentCore.

### Tech Stack

- **Infrastructure**: Terraform (HCL) + AWS CDK (TypeScript), AWS provider
- **Lambda**: Python 3.12, pytest
- **SDK**: TypeScript, esbuild, vitest
- **Mobile SDK (iOS)**: Swift 5.9+, Swift Package Manager
- **Mobile SDK (Android)**: Kotlin 1.9+, Gradle
- **Simulator**: TypeScript, Docker
- **Agent UI**: TypeScript, Next.js 14, Docker
- **AgentCore**: Python 3.12, Bedrock AgentCore

### Project Structure

```
terraform/          - Terraform root module + 11 submodules
  modules/
    s3-data-lake/   - S3 buckets (raw/processed/athena-results)
    glue-catalog/   - Glue database and table schemas
    firehose/       - Kinesis Data Firehose (S3 delivery)
    api-gateway/    - HTTP API + ingest Lambda integration
    security/       - WAF, API Key, Lambda Authorizer
    monitoring/     - CloudWatch dashboards and alarms
    grafana/        - Amazon Managed Grafana workspace
    partition-repair/ - Glue partition auto-repair Lambda
    athena-query/   - Athena query result retrieval Lambda
    agent-ui/       - AgentCore UI hosting infrastructure
    auth/           - Cognito SSO + Lambda@Edge authentication
lambda/             - Python Lambda functions
  authorizer/       - JWT/API Key validation Lambda Authorizer
  ingest/           - HTTP → Firehose bridge
  transform/        - Firehose event transformation (JSON normalization)
  partition-repair/ - Glue partition MSCK REPAIR
  athena-query/     - Athena query execution and result retrieval
  edge-auth/        - CloudFront Lambda@Edge JWT validation (Node.js)
sdk/                - TypeScript RUM SDK (browser client)
mobile-sdk-ios/     - iOS RUM SDK (Swift, SPM)
mobile-sdk-android/ - Android RUM SDK (Kotlin, Gradle)
simulator/          - RUM traffic generator (Docker)
agentcore/          - Bedrock AgentCore RUM analytics agent + Web UI
  agent.py          - Agent main entry (Strands, MCP)
  web/              - Next.js 14 Web UI
  web-app/          - Separate Next.js app (if needed)
cdk/                - AWS CDK (TypeScript) — same infrastructure as Terraform
  lib/constructs/   - 11 Constructs (1:1 mapping with Terraform modules, incl. auth)
  lib/rum-pipeline-stack.ts - Main stack
scripts/            - Build/deploy/test shell scripts
docs/               - Architecture docs, ADRs, runbooks
.claude/            - Claude Code configuration (hooks, skills)
.kiro/              - Kiro agent configuration
tools/              - Prompts, utility scripts
CHANGELOG.md        - Release changelog (Keep a Changelog)
```

### Key Commands

```bash
# Terraform
cd terraform && terraform fmt -recursive
cd terraform && terraform plan
cd terraform && terraform apply

# Lambda tests (per function)
cd lambda/authorizer && python3 -m pytest test_handler.py -v
cd lambda/ingest && python3 -m pytest test_handler.py -v
cd lambda/transform && python3 -m pytest test_handler.py -v
cd lambda/partition-repair && python3 -m pytest test_handler.py -v
cd lambda/athena-query && python3 -m pytest test_handler.py -v

# SDK tests
cd sdk && npm test           # vitest
cd sdk && npm run build      # esbuild

# iOS SDK
cd mobile-sdk-ios && swift build
cd mobile-sdk-ios && swift test

# Android SDK
cd mobile-sdk-android && ./gradlew :rum-sdk:build
cd mobile-sdk-android && ./gradlew :rum-sdk:test

# Simulator
cd simulator && npm test
cd simulator && docker build -t rum-simulator .

# CDK
cd cdk && npm install
cd cdk && npx cdk synth         # Generate CloudFormation
cd cdk && npx cdk deploy        # Deploy

# AgentCore
cd agentcore && python3 agent.py

# Full installation
./scripts/setup.sh all

# Integration test
bash scripts/test-ingestion.sh "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com"
```

### Conventions

- **Comments**: Korean preferred (Korean comments preferred)
- **Terraform**: `terraform fmt` required, modules managed independently
- **Python**: Black formatter, type hints recommended, pytest tests
- **TypeScript**: ESM, strict types, vitest tests
- **Environment separation**: `dev` / `prod` workspace or tfvars
- **Monorepo**: Each package independent (separate node_modules, requirements.txt)
- **Secrets**: Use AWS SSM Parameter Store, no hardcoding
- **Region**: ap-northeast-2 (Seoul) default

---

### Auto-Sync Rules

Rules below are applied automatically after Plan mode exit and on major code changes.

#### Post-Plan Mode Actions
After exiting Plan mode (`/plan`), before starting implementation:

1. **Architecture decision made** -> Update `docs/architecture.md`
2. **Technical choice/trade-off made** -> Create `docs/decisions/ADR-NNN-title.md`
3. **New module added** -> Create `CLAUDE.md` in that module directory
4. **Operational procedure defined** -> Create runbook in `docs/runbooks/`
5. **Changes needed in this file** -> Update relevant sections above

#### Code Change Sync Rules
- New directory under `terraform/modules/` -> Must create `CLAUDE.md` alongside
- New Lambda function added -> Update `lambda/CLAUDE.md`
- API endpoint added/changed -> Update `terraform/modules/api-gateway/` CLAUDE.md
- Infrastructure changed -> Update `docs/architecture.md` Infrastructure section
- New ADR created -> Number sequentially (find max in `docs/decisions/ADR-*.md`)

#### ADR Numbering
Find the highest number in `docs/decisions/ADR-*.md` and increment by 1.
Format: `ADR-NNN-concise-title.md`

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
