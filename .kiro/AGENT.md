# Project Context

## Overview

AWS Custom RUM Pipeline — AWS 서버리스 기반 Real User Monitoring 솔루션.
Web(TypeScript), iOS(Swift), Android(Kotlin) SDK로 RUM 이벤트를 수집하고,
API Gateway → Lambda → Firehose → S3 경로로 처리하여 Glue/Athena로 쿼리 가능하게 만드는 서버리스 파이프라인.
Bedrock AgentCore 기반 AI 분석 에이전트 및 OpenReplay 세션 리플레이 포함.

## Tech Stack

- **Infrastructure**: Terraform (HCL) + AWS CDK (TypeScript), AWS provider
- **Lambda**: Python 3.12, pytest
- **Web SDK**: TypeScript, esbuild, vitest
- **iOS SDK**: Swift 5.9+, Swift Package Manager
- **Android SDK**: Kotlin 1.9+, Gradle
- **Simulator**: TypeScript, Docker, EKS CronJob
- **Agent UI**: TypeScript, Next.js 14, Docker
- **AgentCore**: Python 3.12, Bedrock AgentCore (Strands Agent + MCP)
- **Region**: ap-northeast-2 (서울)

## Project Structure

```
terraform/              - Terraform 루트 모듈 + 12개 서브모듈
  modules/
    s3-data-lake/       - S3 버킷 + 라이프사이클 정책
    glue-catalog/       - Glue DB + 3개 테이블 정의
    firehose/           - Kinesis Firehose + Transform Lambda
    api-gateway/        - HTTP API + Ingest Lambda + Authorizer
    security/           - WAF, API Key, Lambda Authorizer
    monitoring/         - CloudWatch Dashboard (22개 위젯)
    grafana/            - Managed Grafana + Athena Workgroup
    partition-repair/   - Glue 파티션 자동 복구 (EventBridge)
    athena-query/       - Athena SQL 실행 Lambda
    agent-ui/           - CloudFront + ALB + EC2 인프라
    auth/               - Cognito SSO + Lambda@Edge 인증
    openreplay/         - 세션 리플레이 (CF + ALB + EC2 + RDS + Redis + S3)
lambda/                 - Python Lambda 함수 (6개)
  authorizer/           - API Key 검증 (SSM 캐싱)
  ingest/               - HTTP → Firehose 포워딩
  transform/            - 스키마 검증 + PII 제거 + 파티셔닝
  partition-repair/     - MSCK REPAIR TABLE 자동 실행
  athena-query/         - Athena SQL 쿼리 실행
  edge-auth/            - CloudFront Lambda@Edge JWT 검증 (Node.js)
sdk/                    - Web RUM SDK (TypeScript, 12KB)
mobile-sdk-ios/         - iOS RUM SDK (Swift, SPM)
mobile-sdk-android/     - Android RUM SDK (Kotlin, Gradle)
simulator/              - RUM 트래픽 생성기 (TypeScript, Docker)
agentcore/              - Bedrock AgentCore AI 분석 에이전트 + Web UI
  agent.py              - 에이전트 메인 (Strands, MCP)
  web/                  - 간단한 HTML 프로토타입 (레거시)
  web-app/              - Next.js 14 Web UI (메인 채팅 인터페이스)
cdk/                    - AWS CDK (TypeScript) — Terraform 대안
  lib/constructs/       - 12개 Construct (Terraform 모듈 1:1 대응)
  lib/rum-pipeline-stack.ts - 메인 스택
scripts/                - 빌드/배포/테스트 스크립트
tests/                  - 하네스 검증 테스트 (TAP 스타일)
docs/                   - 아키텍처 문서, ADR, 런북
tools/                  - 프롬프트, 유틸리티 스크립트
```

## Key Commands

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

# Web SDK
cd sdk && npm test && npm run build

# iOS SDK
cd mobile-sdk-ios && swift build && swift test

# Android SDK
cd mobile-sdk-android && ./gradlew :rum-sdk:build && ./gradlew :rum-sdk:test

# Simulator
cd simulator && npm test

# CDK
cd cdk && npm install && npx cdk synth && npx cdk deploy

# AgentCore
cd agentcore && pip install -r requirements.txt && python3 agent.py

# 전체 설치
./scripts/setup.sh all

# 하네스 검증
bash tests/run-all.sh

# E2E 통합 테스트
bash scripts/test-ingestion.sh "<api-endpoint>" "<api-key>"
```

## Architecture Flow

```
SDK (Web/iOS/Android) → WAF → HTTP API Gateway → Lambda Authorizer
  → Ingest Lambda → Kinesis Firehose → Transform Lambda → S3 (Parquet)
    → Glue Catalog → Athena → Grafana Dashboard
    → Athena Query Lambda → Bedrock AgentCore (AI 분석)
  → CloudWatch Dashboard (운영 모니터링)
```

## Module Dependency Chain (Terraform)

```
s3-data-lake → glue-catalog → firehose → security → api-gateway
                                            │            │
                                            ▼            ▼
                                        monitoring   partition-repair
                                            │
                                            ▼
                                         grafana → athena-query → agent-ui → auth
```

## Conventions

- **주석**: 한국어 우선 (Korean comments preferred)
- **Terraform**: `terraform fmt` 필수, 모듈별 독립 관리, 모든 리소스에 project/environment/managed_by 태그
- **Python**: Black 포맷터, type hints 권장, pytest 테스트, boto3 호출은 mock 처리
- **TypeScript**: ESM, strict 타입, vitest 테스트
- **환경 분리**: `dev` / `prod` workspace 또는 tfvars
- **시크릿**: AWS SSM Parameter Store 사용, 하드코딩 금지
- **리전**: ap-northeast-2 (서울) 기본
- **모노레포**: 각 패키지 독립 (node_modules, requirements.txt 분리)
- **Lambda**: 각 함수 독립 배포, 환경변수로 설정 주입, IAM 최소 권한
- **이벤트 스키마**: Web/iOS/Android SDK 간 동일 스키마 유지
- **ADR**: `docs/decisions/ADR-NNN-title.md` 형식, 순번 자동 증가
- **커밋**: Conventional Commits (feat:, fix:, docs:, chore:, refactor:, test:)

## Auto-Sync Rules

코드 변경 시 자동으로 적용되는 문서 동기화 규칙:

- `terraform/modules/` 하위에 새 디렉토리 생성 → 해당 모듈 문서 작성
- 새 Lambda 함수 추가 → `lambda/` 모듈 문서 업데이트
- API 엔드포인트 추가/변경 → api-gateway 모듈 문서 업데이트
- 인프라 변경 → `docs/architecture.md` 업데이트
- 아키텍처 결정 → `docs/decisions/ADR-NNN-title.md` 작성
- 운영 절차 정의 → `docs/runbooks/NN-title.md` 작성

## Security

- 파일 쓰기/커밋 시 시크릿 패턴 자동 감지 (AWS Key, JWT, Private Key 등)
- `terraform destroy`, `git push --force`, `rm -rf /` 등 위험 명령 차단
- CORS 설정, IAM 권한, S3 퍼블릭 액세스 등 보안 모범 사례 준수
