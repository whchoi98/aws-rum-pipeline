# AWS Custom RUM Pipeline

> Datadog RUM 대체 AWS 서버리스 기반 Real User Monitoring 파이프라인
>
> AWS Serverless Real User Monitoring pipeline — replacing Datadog RUM

---

## Language / 언어 선택

| [한국어](#한국어) | [English](#english) |
|:-:|:-:|

---

# 한국어

## 목차

| 섹션 | 설명 |
|:-----|:-----|
| [개요](#개요) | 프로젝트 소개 및 목표 |
| [아키텍처](#아키텍처) | 전체 시스템 구성도 |
| [비용 비교](#비용-비교) | Datadog vs AWS 자체 솔루션 |
| [사전 조건](#사전-조건) | 설치 요구사항 |
| [빠른 시작](#빠른-시작) | 설치 및 실행 |
| [프로젝트 구조](#프로젝트-구조) | 디렉토리 레이아웃 |
| [인프라 모듈](#인프라-모듈-terraform) | Terraform 10개 모듈 상세 |
| [Lambda 함수](#lambda-함수) | 5개 Lambda 역할 |
| [Web SDK](#web-sdk-typescript) | 브라우저 RUM 수집 |
| [Mobile SDK](#mobile-sdk) | iOS (Swift) + Android (Kotlin) |
| [시뮬레이터](#시뮬레이터) | 테스트 트래픽 생성 |
| [대시보드](#대시보드) | Grafana + CloudWatch |
| [AI 분석 에이전트](#ai-분석-에이전트) | Bedrock AgentCore |
| [배포 리소스](#배포된-리소스) | 엔드포인트 및 식별자 |
| [테스트](#테스트) | 단위/통합 테스트 실행 |
| [운영](#운영) | 파티션, CronJob, 사용자 관리 |

---

## 개요

Datadog RUM의 높은 비용(월 $1,500~3,000)을 AWS 서버리스 서비스로 대체하여 **~92~96% 비용 절감**을 달성하는 프로젝트입니다.

Web(React/Next.js), iOS(Swift), Android(Kotlin) 앱에서 사용자 행동, 성능, 에러 데이터를 수집하여 S3 Data Lake에 저장하고, Athena + Grafana로 시각화합니다. Bedrock AgentCore 기반 AI 에이전트로 자연어 데이터 분석도 지원합니다.

### 주요 기능

- **Core Web Vitals 모니터링** — LCP, CLS, INP 실시간 수집 및 등급 분석
- **모바일 바이탈** — 앱 시작 시간, 화면 로딩, 프레임 드랍, ANR/크래시 감지
- **에러 추적** — JS 에러, 미처리 예외, 크래시, ANR 자동 수집 및 스택 트레이스
- **사용자 세션 분석** — 세션별 활동 추적, 페이지/화면 전환, 이탈 분석
- **리소스 모니터링** — XHR/Fetch 요청 성능, 응답 시간, 에러율
- **다중 플랫폼** — Web, iOS, Android 단일 파이프라인 통합
- **AI 분석** — 자연어 질문으로 RUM 데이터 자동 분석 (Bedrock Claude Sonnet)

---

## 아키텍처

```
┌─────────────────────────────────────────────────────────────────────┐
│                         데이터 수집 (SDK)                            │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────────────┐ │
│  │ Web SDK  │   │ iOS SDK  │   │ Android  │   │ Simulator        │ │
│  │ (TS/npm) │   │ (Swift)  │   │ (Kotlin) │   │ (EKS CronJob)   │ │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘   └────────┬────────┘ │
│       └───────────────┴──────────────┴──────────────────┘          │
│                              │ HTTPS + x-api-key                    │
└──────────────────────────────┼──────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         보안 계층                                    │
│  WAF WebACL (Rate Limit + Bot Control)                              │
│  HTTP API Gateway → Lambda Authorizer (SSM API Key 검증, 300초 캐싱) │
└──────────────────────────────┬──────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         수집 + 변환                                  │
│  Ingest Lambda → Kinesis Data Firehose → Transform Lambda           │
│                  (5MB/60초 버퍼)         (스키마 검증, PII 제거,       │
│                                          동적 파티셔닝)              │
└──────────────────────────────┬──────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         저장소 (S3 Data Lake)                        │
│  s3://rum-pipeline-data-lake-{account}/                             │
│  └── raw/platform={web|ios|android}/year=/month=/day=/hour=/        │
│      └── events-*.parquet (Snappy 압축)                             │
│                                                                     │
│  Glue Data Catalog: rum_pipeline_db.rum_events                      │
│  파티션 자동 등록: EventBridge (15분) → Partition Repair Lambda       │
└──────────────────────────────┬──────────────────────────────────────┘
                               ▼
┌─────────────────────────────────────────────────────────────────────┐
│                         분석 + 시각화                                │
│  ┌─────────────────┐  ┌──────────────────┐  ┌───────────────────┐  │
│  │ Amazon Managed   │  │ CloudWatch       │  │ Bedrock AgentCore │  │
│  │ Grafana          │  │ Dashboard        │  │ (AI 분석 에이전트) │  │
│  │ - Athena Plugin  │  │ - 22개 위젯      │  │ - Claude Sonnet   │  │
│  │ - Datadog 스타일  │  │ - 한글 라벨      │  │ - 자연어 SQL 생성 │  │
│  │ - 6개 섹션       │  │ - 8개 Row        │  │ - 자동 실행+분석  │  │
│  └─────────────────┘  └──────────────────┘  └───────────────────┘  │
│           ▲                    ▲                      ▲             │
│     Athena Workgroup    API Gateway Metrics    Athena Query Lambda  │
└─────────────────────────────────────────────────────────────────────┘
```

---

## 비용 비교

### Datadog RUM (현재)

| 항목 | 월 비용 |
|------|---------|
| RUM Sessions (Web + Mobile) | $1,500 ~ $3,000 |

### AWS Custom RUM Pipeline (대체)

| 서비스 | 월 비용 (DAU 5만 기준) |
|--------|----------------------|
| API Gateway (HTTP API) | ~$15 |
| Kinesis Data Firehose | ~$30 |
| Lambda (5개 함수) | ~$25 |
| S3 Storage (45GB/90일) | ~$25 |
| WAF (Rate + Bot Control) | ~$19 |
| Amazon Managed Grafana | ~$9 |
| Athena Queries | ~$1 |
| **합계** | **~$124/월** |

**절감율: ~92~96%** ($1,500~3,000 → $124)

---

## 사전 조건

| 도구 | 버전 | 용도 |
|------|------|------|
| AWS CLI | v2+ | AWS 리소스 관리 |
| Terraform | >= 1.5 | 인프라 배포 |
| Node.js | >= 18 | Web SDK, Simulator |
| Python | >= 3.9 | Lambda 함수, 테스트 |
| Docker | latest | Simulator/Agent 이미지 빌드 |
| kubectl | latest | EKS CronJob 배포 (선택) |
| Xcode | 15+ | iOS SDK 빌드 (선택) |
| Android Studio | latest | Android SDK 빌드 (선택) |

---

## 빠른 시작

### 전체 설치 (원클릭)

```bash
git clone <repo-url>
cd rum
./scripts/setup.sh all
```

### 단계별 설치

```bash
# 1. Terraform 인프라 배포
./scripts/setup.sh infra

# 2. Web SDK 빌드 + 테스트
./scripts/setup.sh sdk

# 3. 시뮬레이터 로컬 테스트
./scripts/setup.sh simulator

# 4. Grafana 대시보드 프로비저닝
./scripts/setup.sh grafana

# 5. EKS CronJob 배포 (선택)
./scripts/setup.sh eks

# 6. 전체 테스트 실행
./scripts/setup.sh test
```

---

## 프로젝트 구조

```
rum/
├── terraform/                        # IaC — Terraform 루트 + 10개 모듈
│   ├── main.tf                       # 루트 모듈 (모든 모듈 연결)
│   ├── variables.tf                  # 입력 변수 (region, project_name 등)
│   ├── outputs.tf                    # 출력값 (endpoints, ARNs)
│   └── modules/
│       ├── s3-data-lake/             # S3 버킷 + 라이프사이클 정책
│       ├── glue-catalog/             # Glue DB + 3개 테이블 정의
│       ├── firehose/                 # Kinesis Firehose + Transform Lambda
│       ├── api-gateway/              # HTTP API + Ingest Lambda + Authorizer
│       ├── security/                 # WAF WebACL + SSM API Key
│       ├── monitoring/               # CloudWatch Dashboard (22개 위젯)
│       ├── grafana/                  # Managed Grafana + Athena Workgroup
│       ├── partition-repair/         # Glue 파티션 자동 등록 (EventBridge)
│       ├── athena-query/             # Athena SQL 실행 Lambda
│       └── agent-ui/                 # CloudFront + ALB + EC2 인프라
│
├── lambda/                           # Lambda 함수 (Python 3.12)
│   ├── authorizer/                   # API Key 검증 (SSM 캐싱)
│   ├── ingest/                       # HTTP → Firehose 포워딩
│   ├── transform/                    # 스키마 검증 + PII 제거 + 파티셔닝
│   ├── partition-repair/             # MSCK REPAIR TABLE 자동 실행
│   └── athena-query/                 # Athena SQL 쿼리 실행 (AgentCore용)
│
├── sdk/                              # Web RUM SDK (TypeScript)
│   ├── src/                          # buffer, transport, collectors
│   │   ├── index.ts                  # RumSDK 진입점
│   │   ├── collectors/               # web-vitals, error, navigation, resource
│   │   └── utils/                    # id 생성, 브라우저 컨텍스트
│   ├── tests/                        # vitest 단위 테스트 (14개)
│   └── dist/                         # 빌드 출력 (ESM, CJS, IIFE 12KB)
│
├── mobile-sdk-ios/                   # iOS RUM SDK (Swift 5.9, SPM)
│   ├── Sources/RumSDK/               # SDK 소스
│   │   ├── RumSDK.swift              # 싱글톤 진입점
│   │   ├── Collectors/               # Crash, Screen, Performance, Action
│   │   └── Models/                   # RumEvent (Codable)
│   ├── Tests/RumSDKTests/            # XCTest (11개)
│   └── Package.swift                 # SPM 패키지 정의
│
├── mobile-sdk-android/               # Android RUM SDK (Kotlin 1.9, Gradle)
│   ├── rum-sdk/src/main/kotlin/      # SDK 소스
│   │   └── com/myorg/rum/
│   │       ├── RumSDK.kt             # 싱글톤 진입점
│   │       ├── collectors/           # Crash, ANR, Screen, Performance, Action
│   │       └── models/               # RumEvent (data class)
│   ├── rum-sdk/src/test/kotlin/      # JUnit 테스트 (8개)
│   └── build.gradle.kts              # Gradle 빌드 설정
│
├── simulator/                        # 테스트 트래픽 생성기 (TypeScript)
│   ├── src/                          # 이벤트 생성기 (Web 60%, iOS 25%, Android 15%)
│   ├── k8s/                          # EKS CronJob (5분 간격)
│   ├── Dockerfile                    # node:20-alpine 컨테이너
│   └── tests/                        # vitest 테스트 (3개)
│
├── agentcore/                        # Bedrock AgentCore AI 분석 에이전트
│   ├── agent.py                      # Strands Agent (Claude + Athena MCP)
│   ├── web-app/                      # Next.js 14 채팅 UI
│   │   └── app/api/chat/route.ts     # SSE 스트리밍 API (3라운드 SQL 루프)
│   ├── Dockerfile                    # Python 3.11 arm64 컨테이너
│   └── streamable_http_sigv4.py      # MCP Gateway SigV4 signing
│
├── scripts/                          # 운영 스크립트
│   ├── setup.sh                      # 통합 설치 (6개 Phase)
│   ├── setup-agentcore.sh            # AgentCore 전체 셋업
│   ├── test-ingestion.sh             # E2E 통합 테스트
│   ├── deploy-unified-dashboard.py   # Grafana 대시보드 배포
│   └── provision-grafana.sh          # Grafana 데이터소스 설정
│
├── docs/                             # 문서
│   ├── architecture.md               # 아키텍처 문서
│   ├── decisions/                    # ADR (Architecture Decision Records)
│   ├── runbooks/                     # 운영 런북
│   └── superpowers/
│       ├── specs/                    # 설계 스펙 (4개)
│       └── plans/                    # 구현 계획 (4개)
│
├── CLAUDE.md                         # Claude Code 프로젝트 컨텍스트
└── README.md                         # 이 문서
```

---

## 인프라 모듈 (Terraform)

10개 Terraform 모듈의 의존성 체인:

```
s3-data-lake ──→ glue-catalog ──→ firehose ──→ security ──→ api-gateway
                                                  │              │
                                                  ▼              ▼
                                              monitoring    partition-repair
                                                  │
                                                  ▼
                                               grafana ──→ athena-query ──→ agent-ui
```

| 모듈 | 역할 | 주요 리소스 |
|------|------|-----------|
| `s3-data-lake` | 데이터 저장소 | S3 버킷, 라이프사이클 (raw 90일, aggregated 1년) |
| `glue-catalog` | 메타데이터 | Glue DB, rum_events/hourly_metrics/daily_summary 테이블 |
| `firehose` | 스트림 처리 | Kinesis Firehose, Transform Lambda, Parquet 변환 |
| `api-gateway` | API 진입점 | HTTP API, Ingest Lambda, Authorizer, WAF Association |
| `security` | 인증/보안 | WAF WebACL (Rate+Bot), SSM API Key, Authorizer Lambda |
| `monitoring` | 운영 모니터링 | CloudWatch Dashboard (22개 위젯, 8개 Row) |
| `grafana` | 시각화 | Managed Grafana, Athena Workgroup, IAM Role |
| `partition-repair` | 파티션 관리 | EventBridge (15분) → Lambda → MSCK REPAIR TABLE |
| `athena-query` | AI 에이전트용 | Athena SQL 실행 Lambda (AgentCore Gateway Target) |
| `agent-ui` | AI UI 호스팅 | CloudFront → ALB → EC2 (Next.js) |

---

## Lambda 함수

| 함수 | 런타임 | 메모리 | 타임아웃 | 역할 |
|------|--------|--------|---------|------|
| `rum-pipeline-authorizer` | Python 3.12 | 128MB | 10초 | x-api-key 검증, SSM 캐싱 (300초) |
| `rum-pipeline-ingest` | Python 3.12 | 128MB | 30초 | HTTP 요청 → Firehose PutRecordBatch |
| `rum-pipeline-transform` | Python 3.12 | 256MB | 60초 | 스키마 검증, PII 제거, 동적 파티셔닝 |
| `rum-pipeline-partition-repair` | Python 3.12 | 128MB | 120초 | MSCK REPAIR TABLE (15분 주기) |
| `rum-pipeline-athena-query` | Python 3.12 | 256MB | 60초 | Athena SQL 실행 (SELECT만 허용) |

---

## Web SDK (TypeScript)

### 설치

```bash
npm install @myorg/rum-sdk
```

### 사용법

```typescript
import { RumSDK } from '@myorg/rum-sdk';

RumSDK.init({
  endpoint: 'https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com',
  apiKey: 'your-api-key',
  appVersion: '1.0.0',
  sampleRate: 1.0,        // 0~1 (기본 1.0 = 100%)
  flushInterval: 30000,   // 배치 전송 간격 (ms)
  maxBatchSize: 10,       // 배치 크기
});

// 사용자 식별
RumSDK.setUser('user-123');

// 커스텀 이벤트
RumSDK.addCustomEvent('purchase', { productId: 'ABC', amount: 29900 });
```

### 자동 수집 항목

| Collector | 수집 항목 | event_type |
|-----------|----------|------------|
| WebVitalsCollector | LCP, CLS, INP | performance |
| ErrorCollector | window.onerror, unhandledrejection | error |
| NavigationCollector | 페이지뷰, SPA 라우트 변경 | navigation |
| ResourceCollector | XHR/Fetch 요청 성능 | resource |

### 빌드

```bash
cd sdk
npm install && npm run build

# 출력
# dist/index.mjs  (ESM, tree-shakeable)
# dist/index.cjs  (CommonJS)
# dist/rum-sdk.min.js  (IIFE, 12KB, CDN용)
```

---

## Mobile SDK

### iOS (Swift)

**요구사항:** iOS 15+, Swift 5.9+, Xcode 15+

```swift
// Package.swift에 의존성 추가
dependencies: [
    .package(url: "https://github.com/myorg/rum-sdk-ios.git", from: "0.1.0")
]
```

```swift
import RumSDK

// AppDelegate 또는 @main에서 초기화
RumSDK.shared.configure(RumConfig(
    endpoint: "https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com",
    apiKey: "your-api-key",
    appVersion: "2.1.0"
))

// 사용자 식별
RumSDK.shared.setUser(userId: "user-123")
```

**자동 수집:** 크래시 (NSException + signal), 화면 전환 (VC swizzling), 앱 시작 시간, 탭 액션

### Android (Kotlin)

**요구사항:** minSdk 26, Kotlin 1.9+

```kotlin
// build.gradle.kts
dependencies {
    implementation("com.myorg:rum-sdk:0.1.0")
}
```

```kotlin
import com.myorg.rum.RumSDK
import com.myorg.rum.Config

// Application.onCreate()에서 초기화
RumSDK.init(this, Config(
    endpoint = "https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com",
    apiKey = "your-api-key",
    appVersion = "2.1.0"
))

// 사용자 식별
RumSDK.setUser("user-123")
```

**자동 수집:** 크래시 (UncaughtExceptionHandler), ANR (5초 워치독), 화면 전환 (ActivityLifecycleCallbacks), 앱 시작 시간, 탭 액션

---

## 시뮬레이터

Web/iOS/Android 트래픽을 시뮬레이션하여 파이프라인을 검증합니다.

### 플랫폼 분포

| 플랫폼 | 비율 | 주요 이벤트 |
|--------|------|------------|
| Web | 60% | lcp, cls, inp, page_view, js_error, click |
| iOS | 25% | app_start, screen_load, crash, oom, tap |
| Android | 15% | app_start, frame_drop, crash, anr, tap |

### 시나리오

| 시나리오 | 확률 | LCP 배수 | 에러율 |
|----------|------|----------|--------|
| normal | 70% | 1.0x | 5% |
| slowPage | 20% | 3.0x | 8% |
| errorSpike | 10% | 1.2x | 80% |

### 로컬 실행

```bash
cd simulator
npm install

RUM_API_ENDPOINT=https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com \
RUM_API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text --region ap-northeast-2) \
EVENTS_PER_BATCH=50 \
CONCURRENT_SESSIONS=5 \
npx tsx src/index.ts
```

### EKS CronJob

```bash
# EKS 클러스터 설정
aws eks update-kubeconfig --name eksworkshop --region ap-northeast-2

# 배포
kubectl create namespace rum
kubectl create secret generic rum-api-key --from-literal=api-key="<key>" -n rum
kubectl apply -f simulator/k8s/cronjob.yaml

# 확인
kubectl get cronjob -n rum
```

---

## 대시보드

### Grafana (Datadog RUM 스타일)

**URL:** https://g-c8cc9b0a52.grafana-workspace.ap-northeast-2.amazonaws.com

| 섹션 | Datadog 대응 | 패널 수 |
|------|------------|---------|
| 상단 KPI | Overview | 세션/뷰/에러/크래시/에러율/액션/리소스 |
| 성능 개요 | Performance | LCP/CLS/INP Gauge + 등급분포 + 백분위수 |
| 크래시 및 에러 | Crashes & Errors | 크래시수/에러수/유형별/화면별/추이/상세목록 |
| 리소스 분석 | Resources | 에러리소스/유형별/느린리소스 |
| 모바일 바이탈 | Mobile Vitals | 느린렌더/프레임드랍/앱시작/화면전환 |
| 사용자 세션 | Sessions | 플랫폼/브라우저/OS + 세션탐색기 |

**필터:** 플랫폼 (전체/Web/iOS/Android), 페이지/화면

### CloudWatch Dashboard

**URL:** CloudWatch Console → rum-pipeline-dashboard

22개 위젯, 8개 Row: API 요청/에러/지연시간, Lambda 호출/에러/실행시간/동시실행/스로틀, WAF 허용/차단/Rate Limit/Bot Control, Firehose 수신/전송/바이트

---

## AI 분석 에이전트

**URL:** https://d31gq22ymjjioh.cloudfront.net

Bedrock AgentCore 기반 AI 에이전트로 RUM 데이터를 자연어로 분석합니다.

```
관리자 질문 → Claude Sonnet이 SQL 생성 → Athena 자동 실행 → 결과 분석 → 한국어 답변
```

### 기능

- 최대 3라운드 자동 SQL 실행 루프
- SSE 스트리밍 실시간 응답
- react-markdown + remark-gfm 마크다운 렌더링
- 6개 빠른 질문 버튼

### 인프라

| 구성 | 값 |
|------|-----|
| CloudFront | d31gq22ymjjioh.cloudfront.net |
| ALB SG | CloudFront Prefix List (pl-22a6434b) only |
| EC2 | t4g.large (mgmt-vpc) |
| 모델 | global.anthropic.claude-sonnet-4-6 |
| Runtime | rumAnalysisAgent-6f5T6RBNfQ |
| Gateway | rum-athena-gw-kmdmf4mnby |
| Memory | rum_analysis_memory-HVOH4wCK6w |

---

## 배포된 리소스

| 리소스 | 값 |
|--------|-----|
| API Endpoint | `https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com` |
| Grafana | `https://g-c8cc9b0a52.grafana-workspace.ap-northeast-2.amazonaws.com` |
| Agent UI | `https://d31gq22ymjjioh.cloudfront.net` |
| SSO Portal | `https://d-9b6773f833.awsapps.com/start` |
| S3 Data Lake | `rum-pipeline-data-lake-061525506239` |
| Glue Database | `rum_pipeline_db` |
| Athena Workgroup | `rum-pipeline-athena` |
| CW Dashboard | `rum-pipeline-dashboard` |
| Region | `ap-northeast-2` |

---

## 테스트

```bash
# Lambda 단위 테스트 (Python)
cd lambda/authorizer && python3 -m pytest test_handler.py -v   # 8 tests
cd lambda/ingest && python3 -m pytest test_handler.py -v       # 7 tests
cd lambda/transform && python3 -m pytest test_handler.py -v    # 8 tests

# Web SDK 단위 테스트 (TypeScript)
cd sdk && npx vitest run                                       # 14 tests

# 시뮬레이터 테스트
cd simulator && npx vitest run                                 # 3 tests

# E2E 통합 테스트
API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text --region ap-northeast-2)
./scripts/test-ingestion.sh \
  https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com "$API_KEY"
```

---

## 운영

### Glue 파티션 자동 등록

EventBridge가 15분마다 `rum-pipeline-partition-repair` Lambda를 실행하여 `MSCK REPAIR TABLE rum_events`를 수행합니다. 새로운 Firehose 파티션이 자동으로 Athena에서 조회 가능해집니다.

### EKS 시뮬레이터 관리

```bash
# CronJob 상태 확인
kubectl get cronjob -n rum

# 수동 실행
kubectl create job rum-sim-manual --from=cronjob/rum-simulator -n rum

# 로그 확인
kubectl logs job/rum-sim-manual -n rum

# 일시 중지
kubectl patch cronjob rum-simulator -n rum -p '{"spec":{"suspend":true}}'
```

### Grafana 사용자 관리

```bash
# SSO 사용자 목록
aws identitystore list-users --identity-store-id d-9b6773f833 --region ap-northeast-2

# Grafana Admin 추가
USER_ID=$(aws identitystore list-users --identity-store-id d-9b6773f833 \
  --query 'Users[?UserName==`username`].UserId | [0]' --output text --region ap-northeast-2)
aws grafana update-permissions --workspace-id g-c8cc9b0a52 \
  --update-instruction-batch "[{\"action\":\"ADD\",\"role\":\"ADMIN\",\"users\":[{\"id\":\"$USER_ID\",\"type\":\"SSO_USER\"}]}]" \
  --region ap-northeast-2
```

### API Key 로테이션

```bash
# 현재 키 확인
aws ssm get-parameter --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text --region ap-northeast-2

# 새 키 추가 (쉼표 구분)
aws ssm put-parameter --name /rum-pipeline/dev/api-keys \
  --value "기존키,새키" --type SecureString --overwrite --region ap-northeast-2
```

---

---

# English

## Table of Contents

| Section | Description |
|:--------|:-----------|
| [Overview](#overview) | Project introduction and goals |
| [Architecture](#architecture) | System architecture diagram |
| [Cost Comparison](#cost-comparison) | Datadog vs AWS custom solution |
| [Prerequisites](#prerequisites) | Installation requirements |
| [Quick Start](#quick-start) | Installation and execution |
| [Project Structure](#project-structure-1) | Directory layout |
| [Infrastructure](#infrastructure-modules-terraform) | 10 Terraform modules |
| [Web SDK](#web-sdk-typescript-1) | Browser RUM collection |
| [Mobile SDKs](#mobile-sdks) | iOS (Swift) + Android (Kotlin) |
| [Simulator](#simulator) | Test traffic generation |
| [Dashboards](#dashboards) | Grafana + CloudWatch |
| [AI Analysis Agent](#ai-analysis-agent) | Bedrock AgentCore |
| [Deployed Resources](#deployed-resources) | Endpoints and identifiers |
| [Testing](#testing) | Unit and integration tests |
| [Operations](#operations) | Partitions, CronJob, user management |

---

## Overview

This project replaces Datadog RUM ($1,500~3,000/month) with an AWS serverless pipeline, achieving **~92-96% cost reduction**.

It collects user behavior, performance, and error data from Web (React/Next.js), iOS (Swift), and Android (Kotlin) applications, stores them in an S3 Data Lake as Parquet files, and visualizes through Athena + Grafana. A Bedrock AgentCore AI agent enables natural language data analysis.

### Key Features

- **Core Web Vitals** — LCP, CLS, INP real-time collection and rating analysis
- **Mobile Vitals** — App start time, screen load, frame drops, ANR/crash detection
- **Error Tracking** — JS errors, unhandled exceptions, crashes, ANR with stack traces
- **Session Analysis** — Per-session activity tracking, page/screen transitions
- **Resource Monitoring** — XHR/Fetch request performance, response times, error rates
- **Multi-Platform** — Web, iOS, Android unified into a single pipeline
- **AI Analysis** — Natural language RUM data analysis (Bedrock Claude Sonnet)

---

## Cost Comparison

| | Datadog RUM | AWS Custom Pipeline |
|---|---|---|
| Monthly Cost (50K DAU) | $1,500 ~ $3,000 | **~$124** |
| Savings | - | **~92-96%** |

---

## Prerequisites

- AWS CLI v2+, Terraform >= 1.5, Node.js >= 18, Python >= 3.9
- Docker (for Simulator/Agent image builds)
- kubectl (optional, for EKS CronJob)
- Xcode 15+ (optional, for iOS SDK)
- Android Studio (optional, for Android SDK)

---

## Quick Start

```bash
# Full installation
./scripts/setup.sh all

# Step-by-step
./scripts/setup.sh infra       # 1. Terraform infrastructure
./scripts/setup.sh sdk         # 2. Web SDK build + test
./scripts/setup.sh simulator   # 3. Simulator local test
./scripts/setup.sh grafana     # 4. Grafana dashboard provisioning
./scripts/setup.sh eks         # 5. EKS CronJob deployment
./scripts/setup.sh test        # 6. Full test suite
```

---

## Architecture

```
SDK (Web/iOS/Android) → WAF → HTTP API → Lambda Authorizer → Ingest Lambda
    → Kinesis Firehose → Transform Lambda → S3 Data Lake (Parquet)
        → Athena → Grafana Dashboards
        → Athena Query Lambda → Bedrock AgentCore (AI Analysis)
    → CloudWatch Dashboard (Operations)
```

---

## Infrastructure Modules (Terraform)

| Module | Purpose |
|--------|---------|
| `s3-data-lake` | S3 bucket with lifecycle policies |
| `glue-catalog` | Glue database and table definitions |
| `firehose` | Kinesis Firehose with Lambda transform |
| `api-gateway` | HTTP API with Ingest Lambda and Authorizer |
| `security` | WAF WebACL (Rate + Bot) and SSM API Key |
| `monitoring` | CloudWatch Dashboard (22 widgets) |
| `grafana` | Amazon Managed Grafana + Athena Workgroup |
| `partition-repair` | Auto-register Glue partitions (15min) |
| `athena-query` | Athena SQL execution Lambda for AgentCore |
| `agent-ui` | CloudFront + ALB + EC2 for AI chat UI |

---

## Web SDK (TypeScript)

```typescript
import { RumSDK } from '@myorg/rum-sdk';

RumSDK.init({
  endpoint: 'https://your-api.execute-api.region.amazonaws.com',
  apiKey: 'your-api-key',
  appVersion: '1.0.0',
});
```

Auto-collects: Core Web Vitals (LCP/CLS/INP), JS errors, page views, SPA route changes, XHR/Fetch performance.

Bundle size: **12KB** (IIFE, minified).

---

## Mobile SDKs

### iOS (Swift)

```swift
import RumSDK

RumSDK.shared.configure(RumConfig(
    endpoint: "https://your-api.execute-api.region.amazonaws.com",
    apiKey: "your-api-key",
    appVersion: "2.1.0"
))
```

Auto-collects: Crashes, screen transitions, app start time, tap actions. Requires iOS 15+, Swift 5.9+.

### Android (Kotlin)

```kotlin
import com.myorg.rum.RumSDK
import com.myorg.rum.Config

RumSDK.init(context, Config(
    endpoint = "https://your-api.execute-api.region.amazonaws.com",
    apiKey = "your-api-key",
    appVersion = "2.1.0"
))
```

Auto-collects: Crashes, ANR (5s watchdog), screen transitions, app start time, tap actions. Requires minSdk 26, Kotlin 1.9+.

---

## Dashboards

### Grafana (Datadog RUM Style)

Datadog-style unified dashboard with 6 sections: KPI bar, Performance Overview, Crashes & Errors, Resources Analysis, Mobile Vitals, User Sessions. Includes platform and page filters.

### CloudWatch Dashboard

22 operational widgets across 8 rows: API Gateway, Lambda functions, WAF, and Firehose metrics with Korean labels.

---

## AI Analysis Agent

**URL:** https://d31gq22ymjjioh.cloudfront.net

Chat-based AI agent powered by Bedrock Claude Sonnet. Ask questions in natural language — the agent generates SQL, auto-executes on Athena, and returns analyzed results.

Supports up to 3-round SQL execution loops with SSE streaming.

---

## Deployed Resources

| Resource | Value |
|----------|-------|
| API Endpoint | `https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com` |
| Grafana | `https://g-c8cc9b0a52.grafana-workspace.ap-northeast-2.amazonaws.com` |
| Agent UI | `https://d31gq22ymjjioh.cloudfront.net` |
| SSO Portal | `https://d-9b6773f833.awsapps.com/start` |
| S3 Data Lake | `rum-pipeline-data-lake-061525506239` |
| Region | `ap-northeast-2` |

---

## Testing

```bash
# Lambda unit tests (Python)
cd lambda/authorizer && python3 -m pytest test_handler.py -v
cd lambda/ingest && python3 -m pytest test_handler.py -v
cd lambda/transform && python3 -m pytest test_handler.py -v

# Web SDK unit tests (TypeScript)
cd sdk && npx vitest run

# Simulator tests
cd simulator && npx vitest run

# E2E integration tests
./scripts/test-ingestion.sh <api-endpoint> <api-key>
```

---

## Operations

### Glue Partition Auto-Registration

EventBridge triggers `MSCK REPAIR TABLE` every 15 minutes via Lambda, ensuring new Firehose partitions are discoverable by Athena.

### EKS Simulator Management

```bash
kubectl get cronjob -n rum                                    # Status
kubectl create job test --from=cronjob/rum-simulator -n rum   # Manual run
kubectl patch cronjob rum-simulator -n rum -p '{"spec":{"suspend":true}}'  # Pause
```

### API Key Rotation

```bash
aws ssm put-parameter --name /rum-pipeline/dev/api-keys \
  --value "old-key,new-key" --type SecureString --overwrite --region ap-northeast-2
```

---

## License

Internal use only.
