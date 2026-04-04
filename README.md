# AWS Custom RUM Pipeline

[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Terraform](https://img.shields.io/badge/Terraform-%3E%3D1.5-623CE4.svg)](https://www.terraform.io/)
[![CDK](https://img.shields.io/badge/AWS_CDK-TypeScript-FF9900.svg)](https://aws.amazon.com/cdk/)

A serverless Real User Monitoring pipeline built on AWS — collect, store, query, and visualize RUM data at scale.

AWS 서버리스 기반 Real User Monitoring 파이프라인 — RUM 데이터를 대규모로 수집, 저장, 쿼리, 시각화합니다.

🇺🇸 [English](#english) | 🇰🇷 [한국어](#한국어)

---

# English

## Overview

AWS Custom RUM Pipeline is a serverless Real User Monitoring solution that replaces expensive commercial RUM services. It collects user behavior, performance, and error data from Web, iOS, and Android applications through a unified ingestion pipeline, stores events as Parquet files in S3, and provides analysis through Athena + Grafana dashboards and a Bedrock AgentCore AI agent.

The pipeline processes approximately 1.8M events/day for 50K DAU at an estimated cost of ~$124/month.

## Features

- **Core Web Vitals Monitoring** — Real-time collection and rating analysis of LCP, CLS, and INP metrics.
- **Multi-Platform Support** — Web (TypeScript), iOS (Swift), and Android (Kotlin) SDKs unified into a single pipeline.
- **Error and Crash Tracking** — JS errors, unhandled exceptions, crashes, and ANR with automatic stack trace collection.
- **AI-Powered Analysis** — Natural language RUM data analysis via Bedrock Claude Sonnet with auto-generated Athena SQL.
- **Admin Dashboard** — 43-panel Grafana dashboard across 9 sections with real-time KPIs, CWV gauges, error trends, and session explorer.
- **Infrastructure as Code** — Dual IaC support with Terraform (11 modules) and AWS CDK (11 constructs).
- **SSO Authentication** — CloudFront + Lambda@Edge + Cognito SSO for Agent UI access control with per-user memory.

## Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2+ | AWS resource management |
| Terraform | >= 1.5 | Infrastructure deployment |
| Node.js | >= 18 | Web SDK, Simulator, CDK |
| Python | >= 3.9 | Lambda functions, tests |
| Docker | latest | Simulator/Agent image builds |
| kubectl | latest | EKS CronJob deployment (optional) |
| Xcode | 15+ | iOS SDK build (optional) |
| Android Studio | latest | Android SDK build (optional) |

## Installation

```bash
# Clone the repository
git clone https://github.com/whchoi98/aws-rum-pipeline.git
cd aws-rum-pipeline

# One-click full installation
./scripts/setup.sh all

# Or step-by-step
./scripts/setup.sh infra       # 1. Terraform infrastructure
./scripts/setup.sh sdk         # 2. Web SDK build + test
./scripts/setup.sh simulator   # 3. Simulator local test
./scripts/setup.sh grafana     # 4. Grafana dashboard provisioning
./scripts/setup.sh eks         # 5. EKS CronJob deployment (optional)
./scripts/setup.sh test        # 6. Full test suite
```

## Usage

### Web SDK

```typescript
import { RumSDK } from '@myorg/rum-sdk';

RumSDK.init({
  endpoint: 'https://<api-id>.execute-api.ap-northeast-2.amazonaws.com',
  apiKey: 'your-api-key',
  appVersion: '1.0.0',
  sampleRate: 1.0,        // 0~1 (default 1.0 = 100%)
  flushInterval: 30000,   // batch interval (ms)
  maxBatchSize: 10,       // batch size
});

RumSDK.setUser('user-123');
RumSDK.addCustomEvent('purchase', { productId: 'ABC', amount: 29900 });
// Auto-collects: LCP, CLS, INP, JS errors, page views, XHR/Fetch performance
```

### iOS SDK (Swift)

```swift
import RumSDK

RumSDK.shared.configure(RumConfig(
    endpoint: "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com",
    apiKey: "your-api-key",
    appVersion: "2.1.0"
))
RumSDK.shared.setUser(userId: "user-123")
// Auto-collects: crashes, screen transitions, app start time, tap actions
```

### Android SDK (Kotlin)

```kotlin
import com.myorg.rum.RumSDK
import com.myorg.rum.Config

RumSDK.init(context, Config(
    endpoint = "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com",
    apiKey = "your-api-key",
    appVersion = "2.1.0"
))
RumSDK.setUser("user-123")
// Auto-collects: crashes, ANR, screen transitions, app start time, tap actions
```

## Configuration

| Variable | Description | Default |
|----------|-------------|---------|
| `aws_region` | AWS deployment region | `ap-northeast-2` |
| `environment` | Environment name (dev/staging/prod) | `dev` |
| `project_name` | Resource naming prefix | `rum-pipeline` |
| `vpc_id` | VPC ID for Agent UI | (required) |
| `public_subnet_ids` | Public subnets for ALB | (required) |
| `agentcore_endpoint_arn` | Bedrock AgentCore ARN | (required) |
| `sso_metadata_url` | SSO SAML metadata URL | `""` (disabled) |
| `allowed_origins` | CORS allowed origins | `["*"]` |

Set values in `terraform/terraform.tfvars` (see `terraform.tfvars.example`).

## Project Structure

```
aws-rum-pipeline/
├── terraform/                    # IaC — Terraform root + 11 modules
│   └── modules/
│       ├── s3-data-lake/         # S3 buckets + lifecycle policies
│       ├── glue-catalog/         # Glue DB + 3 table definitions
│       ├── firehose/             # Kinesis Firehose + Transform Lambda
│       ├── api-gateway/          # HTTP API + Ingest Lambda
│       ├── security/             # WAF WebACL + SSM API Key
│       ├── monitoring/           # CloudWatch Dashboard (22 widgets)
│       ├── grafana/              # Managed Grafana + Athena Workgroup
│       ├── partition-repair/     # Glue partition auto-repair (EventBridge)
│       ├── athena-query/         # Athena SQL execution Lambda
│       ├── agent-ui/             # CloudFront + ALB + EC2
│       └── auth/                 # Cognito SSO + Lambda@Edge
├── lambda/                       # Lambda functions (Python 3.12)
│   ├── authorizer/               # API Key validation (SSM cached)
│   ├── ingest/                   # HTTP → Firehose forwarding
│   ├── transform/                # Schema validation + PII strip + partitioning
│   ├── partition-repair/         # MSCK REPAIR TABLE
│   ├── athena-query/             # Athena SQL execution (AgentCore)
│   └── edge-auth/                # CloudFront Lambda@Edge JWT (Node.js)
├── sdk/                          # Web RUM SDK (TypeScript, 12KB)
├── mobile-sdk-ios/               # iOS RUM SDK (Swift 5.9, SPM)
├── mobile-sdk-android/           # Android RUM SDK (Kotlin 1.9, Gradle)
├── simulator/                    # Traffic generator (TypeScript, Docker, EKS)
├── agentcore/                    # Bedrock AgentCore AI agent + Next.js UI
├── cdk/                          # AWS CDK (TypeScript) — Terraform alternative
├── scripts/                      # Build/deploy/test scripts
└── docs/                         # Architecture, ADRs, runbooks
```

## Testing

```bash
# Lambda unit tests (Python)
cd lambda/authorizer && python3 -m pytest test_handler.py -v   # 8 tests
cd lambda/ingest && python3 -m pytest test_handler.py -v       # 7 tests
cd lambda/transform && python3 -m pytest test_handler.py -v    # 8 tests

# Web SDK unit tests (TypeScript)
cd sdk && npx vitest run                                       # 14 tests

# Simulator tests
cd simulator && npx vitest run                                 # 3 tests

# iOS SDK tests
cd mobile-sdk-ios && swift test                                # 11 tests

# Android SDK tests
cd mobile-sdk-android && ./gradlew :rum-sdk:test               # 8 tests

# E2E integration test
./scripts/test-ingestion.sh <api-endpoint> <api-key>
```

## Contributing

1. Fork the repository.
2. Create a feature branch: `git checkout -b feat/my-feature`
3. Commit changes: `git commit -m "feat: add new feature"`
4. Push to your fork: `git push origin feat/my-feature`
5. Open a Pull Request.

Commit messages follow [Conventional Commits](https://www.conventionalcommits.org/): `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`.

## License

This project is licensed under the MIT License. See the [LICENSE](LICENSE) file for details.

## Contact

- **Maintainer:** [whchoi98](https://github.com/whchoi98)
- **Issues:** [GitHub Issues](https://github.com/whchoi98/aws-rum-pipeline/issues)
- **Repository:** [github.com/whchoi98/aws-rum-pipeline](https://github.com/whchoi98/aws-rum-pipeline)

---

# 한국어

## 개요

AWS Custom RUM Pipeline은 비용이 높은 상용 RUM 서비스를 대체하는 서버리스 Real User Monitoring 솔루션입니다. Web, iOS, Android 앱에서 사용자 행동, 성능, 에러 데이터를 통합 수집 파이프라인으로 수집하고, S3에 Parquet 파일로 저장하며, Athena + Grafana 대시보드와 Bedrock AgentCore AI 에이전트를 통해 분석합니다.

DAU 5만 기준 약 180만 이벤트/일을 처리하며, 예상 비용은 월 ~$124입니다.

## 주요 기능

- **Core Web Vitals 모니터링** — LCP, CLS, INP 실시간 수집 및 등급 분석
- **다중 플랫폼 지원** — Web(TypeScript), iOS(Swift), Android(Kotlin) SDK를 단일 파이프라인으로 통합
- **에러 및 크래시 추적** — JS 에러, 미처리 예외, 크래시, ANR 자동 수집 및 스택 트레이스
- **AI 기반 분석** — Bedrock Claude Sonnet으로 자연어 RUM 데이터 분석, Athena SQL 자동 생성
- **관리자 대시보드** — 43개 패널 9개 섹션의 Grafana 대시보드 (실시간 KPI, CWV 게이지, 에러 추이, 세션 탐색기)
- **Infrastructure as Code** — Terraform(11개 모듈)과 AWS CDK(11개 Construct) 듀얼 IaC 지원
- **SSO 인증** — CloudFront + Lambda@Edge + Cognito SSO로 Agent UI 접근 제어 및 사용자별 메모리

## 사전 요구 사항

| 도구 | 버전 | 용도 |
|------|------|------|
| AWS CLI | v2+ | AWS 리소스 관리 |
| Terraform | >= 1.5 | 인프라 배포 |
| Node.js | >= 18 | Web SDK, Simulator, CDK |
| Python | >= 3.9 | Lambda 함수, 테스트 |
| Docker | latest | Simulator/Agent 이미지 빌드 |
| kubectl | latest | EKS CronJob 배포 (선택) |
| Xcode | 15+ | iOS SDK 빌드 (선택) |
| Android Studio | latest | Android SDK 빌드 (선택) |

## 설치 방법

```bash
# 리포지토리 클론
git clone https://github.com/whchoi98/aws-rum-pipeline.git
cd aws-rum-pipeline

# 원클릭 전체 설치
./scripts/setup.sh all

# 또는 단계별 설치
./scripts/setup.sh infra       # 1. Terraform 인프라 배포
./scripts/setup.sh sdk         # 2. Web SDK 빌드 + 테스트
./scripts/setup.sh simulator   # 3. 시뮬레이터 로컬 테스트
./scripts/setup.sh grafana     # 4. Grafana 대시보드 프로비저닝
./scripts/setup.sh eks         # 5. EKS CronJob 배포 (선택)
./scripts/setup.sh test        # 6. 전체 테스트 실행
```

## 사용법

### Web SDK

```typescript
import { RumSDK } from '@myorg/rum-sdk';

RumSDK.init({
  endpoint: 'https://<api-id>.execute-api.ap-northeast-2.amazonaws.com',
  apiKey: 'your-api-key',
  appVersion: '1.0.0',
  sampleRate: 1.0,        // 0~1 (기본 1.0 = 100%)
  flushInterval: 30000,   // 배치 전송 간격 (ms)
  maxBatchSize: 10,       // 배치 크기
});

RumSDK.setUser('user-123');
RumSDK.addCustomEvent('purchase', { productId: 'ABC', amount: 29900 });
// 자동 수집: LCP, CLS, INP, JS 에러, 페이지뷰, XHR/Fetch 성능
```

### iOS SDK (Swift)

```swift
import RumSDK

RumSDK.shared.configure(RumConfig(
    endpoint: "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com",
    apiKey: "your-api-key",
    appVersion: "2.1.0"
))
RumSDK.shared.setUser(userId: "user-123")
// 자동 수집: 크래시, 화면 전환, 앱 시작 시간, 탭 액션
```

### Android SDK (Kotlin)

```kotlin
import com.myorg.rum.RumSDK
import com.myorg.rum.Config

RumSDK.init(context, Config(
    endpoint = "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com",
    apiKey = "your-api-key",
    appVersion = "2.1.0"
))
RumSDK.setUser("user-123")
// 자동 수집: 크래시, ANR, 화면 전환, 앱 시작 시간, 탭 액션
```

## 환경 설정

| 변수명 | 설명 | 기본값 |
|--------|------|--------|
| `aws_region` | AWS 배포 리전 | `ap-northeast-2` |
| `environment` | 환경 이름 (dev/staging/prod) | `dev` |
| `project_name` | 리소스 이름 접두사 | `rum-pipeline` |
| `vpc_id` | Agent UI용 VPC ID | (필수) |
| `public_subnet_ids` | ALB용 퍼블릭 서브넷 | (필수) |
| `agentcore_endpoint_arn` | Bedrock AgentCore ARN | (필수) |
| `sso_metadata_url` | SSO SAML 메타데이터 URL | `""` (비활성화) |
| `allowed_origins` | CORS 허용 오리진 | `["*"]` |

`terraform/terraform.tfvars`에 설정합니다 (`terraform.tfvars.example` 참조).

## 프로젝트 구조

```
aws-rum-pipeline/
├── terraform/                    # IaC — Terraform 루트 + 11개 모듈
│   └── modules/
│       ├── s3-data-lake/         # S3 버킷 + 라이프사이클 정책
│       ├── glue-catalog/         # Glue DB + 3개 테이블 정의
│       ├── firehose/             # Kinesis Firehose + Transform Lambda
│       ├── api-gateway/          # HTTP API + Ingest Lambda
│       ├── security/             # WAF WebACL + SSM API Key
│       ├── monitoring/           # CloudWatch 대시보드 (22개 위젯)
│       ├── grafana/              # Managed Grafana + Athena 워크그룹
│       ├── partition-repair/     # Glue 파티션 자동 복구 (EventBridge)
│       ├── athena-query/         # Athena SQL 실행 Lambda
│       ├── agent-ui/             # CloudFront + ALB + EC2
│       └── auth/                 # Cognito SSO + Lambda@Edge
├── lambda/                       # Lambda 함수 (Python 3.12)
│   ├── authorizer/               # API Key 검증 (SSM 캐싱)
│   ├── ingest/                   # HTTP → Firehose 포워딩
│   ├── transform/                # 스키마 검증 + PII 제거 + 파티셔닝
│   ├── partition-repair/         # MSCK REPAIR TABLE
│   ├── athena-query/             # Athena SQL 실행 (AgentCore용)
│   └── edge-auth/                # CloudFront Lambda@Edge JWT 검증 (Node.js)
├── sdk/                          # Web RUM SDK (TypeScript, 12KB)
├── mobile-sdk-ios/               # iOS RUM SDK (Swift 5.9, SPM)
├── mobile-sdk-android/           # Android RUM SDK (Kotlin 1.9, Gradle)
├── simulator/                    # 트래픽 생성기 (TypeScript, Docker, EKS)
├── agentcore/                    # Bedrock AgentCore AI 에이전트 + Next.js UI
├── cdk/                          # AWS CDK (TypeScript) — Terraform 대안
├── scripts/                      # 빌드/배포/테스트 스크립트
└── docs/                         # 아키텍처, ADR, 런북
```

## 테스트

```bash
# Lambda 단위 테스트 (Python)
cd lambda/authorizer && python3 -m pytest test_handler.py -v   # 8개 테스트
cd lambda/ingest && python3 -m pytest test_handler.py -v       # 7개 테스트
cd lambda/transform && python3 -m pytest test_handler.py -v    # 8개 테스트

# Web SDK 단위 테스트 (TypeScript)
cd sdk && npx vitest run                                       # 14개 테스트

# 시뮬레이터 테스트
cd simulator && npx vitest run                                 # 3개 테스트

# iOS SDK 테스트
cd mobile-sdk-ios && swift test                                # 11개 테스트

# Android SDK 테스트
cd mobile-sdk-android && ./gradlew :rum-sdk:test               # 8개 테스트

# E2E 통합 테스트
./scripts/test-ingestion.sh <api-endpoint> <api-key>
```

## 기여 방법

1. 리포지토리를 Fork합니다.
2. 기능 브랜치를 생성합니다: `git checkout -b feat/my-feature`
3. 변경사항을 커밋합니다: `git commit -m "feat: 새 기능 추가"`
4. Fork에 푸시합니다: `git push origin feat/my-feature`
5. Pull Request를 생성합니다.

커밋 메시지는 [Conventional Commits](https://www.conventionalcommits.org/) 형식을 따릅니다: `feat:`, `fix:`, `docs:`, `chore:`, `refactor:`, `test:`.

## 라이선스

이 프로젝트는 MIT 라이선스에 따라 배포됩니다. 자세한 내용은 [LICENSE](LICENSE) 파일을 참조하십시오.

## 연락처

- **메인테이너:** [whchoi98](https://github.com/whchoi98)
- **이슈:** [GitHub Issues](https://github.com/whchoi98/aws-rum-pipeline/issues)
- **리포지토리:** [github.com/whchoi98/aws-rum-pipeline](https://github.com/whchoi98/aws-rum-pipeline)
