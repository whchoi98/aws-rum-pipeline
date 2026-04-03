# AWS Custom RUM Pipeline — Design Spec

**Date:** 2026-04-01
**Status:** Draft
## 1. Overview

AWS 서버리스 기반 Custom RUM(Real User Monitoring) 파이프라인.
Web과 Mobile에서 사용자 행동, 성능, 에러를 수집하여 S3 Data Lake에 저장하고, Athena + Grafana로 분석/시각화한다.

### Goals

- AWS 서버리스 기반 **경제적인 RUM** (~$124/월, DAU 5만 기준)
- Web + Mobile **단일 파이프라인**으로 통합
- Core Web Vitals, 사용자 행동, 에러 모니터링 지원
- 세션 리플레이는 Phase 2로 분리

### Non-Goals

- 세션 리플레이 (Phase 2)
- 백엔드 APM/분산 추적 (별도 시스템)
- 실시간(<1초) 알림 (준실시간 5분 간격으로 충분)

### Constraints

- OpenSearch 클러스터 사용 불가 (비용 문제로 다른 용도 전용)
- 기존 CloudWatch(로그/메트릭) 활용
- 데이터 보관: Raw 90일, Aggregated 1년

## 2. Architecture

6-Layer 서버리스 아키텍처:

```
① SDK (Web/Mobile)
    ↓ HTTPS (batched, gzip)
② API Gateway (HTTP API)
    ↓ Service Integration (Lambda 없이 직접 연결)
③ Kinesis Data Firehose + Lambda Transform
    ↓ Parquet 변환 + 동적 파티셔닝
④ S3 Data Lake
    ↓
⑤ EventBridge + Lambda (집계)
    ↓
⑥ Athena + Grafana (쿼리/시각화/알림)
```

### 예상 월 비용 (DAU 5만 기준)

| 서비스 | 월 비용 |
|--------|---------|
| API Gateway (HTTP API) | ~$15 |
| Kinesis Firehose | ~$30 |
| Lambda (Transform + Aggregation) | ~$20 |
| S3 Storage | ~$25 |
| Athena Queries | ~$30 |
| Glue Catalog | ~$1 |
| Grafana (ECS Fargate) | ~$30 |
| **합계** | **~$150** |

## 3. Layer ① — SDK

### 3.1 Web SDK

- **구현:** 자체 경량 SDK (TypeScript), gzip 후 <10KB
- **수집 이벤트:**
  - **Performance:** LCP, FID/INP, CLS, TTFB, FCP (`PerformanceObserver` API)
  - **Navigation:** 페이지뷰, SPA 라우트 변경 (`MutationObserver`, History API)
  - **User Action:** 클릭, 스크롤 깊이, 폼 인터랙션
  - **Error:** JS 에러 (`window.onerror`), 미처리 프로미스 (`onunhandledrejection`), 콘솔 에러
  - **Resource:** XHR/Fetch 요청, 응답 시간, 상태 코드

### 3.2 Mobile SDK

- **구현:** 프레임워크별 SDK 래퍼 (React Native / Flutter / Native)
- **수집 이벤트:**
  - **Performance:** 앱 시작 시간, 화면 로딩, 프레임 드랍
  - **Screen:** 화면 진입/이탈, 체류 시간
  - **User Action:** 탭, 스와이프, 스크롤
  - **Crash:** 미처리 예외, ANR (Android), OOM
  - **Network:** API 호출, 응답 시간, 에러율

### 3.3 통합 이벤트 스키마

Web과 Mobile이 동일한 스키마를 공유하여 백엔드 파이프라인을 단일화한다.

```json
{
  "session_id": "uuid",
  "user_id": "hashed_id | anonymous",
  "device_id": "uuid",
  "timestamp": 1712000000000,
  "platform": "web | ios | android",
  "app_version": "2.1.0",
  "event_type": "performance | action | error | navigation | resource",
  "event_name": "lcp | click | js_error | page_view | xhr",
  "payload": {},
  "context": {
    "url": "/products/123",
    "screen_name": "ProductDetail",
    "device": { "os": "iOS 17", "model": "iPhone 15", "browser": "Chrome 120" },
    "geo": {},
    "connection": { "type": "4g", "rtt": 50 }
  }
}
```

### 3.4 전송 전략

- **배치 전송:** 30초 간격 또는 10개 누적 시 전송, gzip 압축
- **오프라인 큐잉:** IndexedDB (Web) / SQLite (Mobile)에 버퍼링, 재연결 시 전송
- **재시도:** Exponential backoff (최대 3회)
- **페이지 이탈:** `navigator.sendBeacon` (Web), flush on app pause (Mobile)

### 3.5 프라이버시 & 샘플링

- **PII 보호:** 이메일/전화번호 자동 마스킹, 입력 필드 값 미수집, user_id 해시 처리, IP 미저장 (GeoIP 변환 후 폐기)
- **샘플링:** 기본 100% (중규모 감당 가능), 에러는 항상 100%, 트래픽 증가 시 세션 기반 샘플링, 서버사이드 config로 원격 제어

## 4. Layer ② — Ingestion (API Gateway)

### 엔드포인트

```
POST /v1/events          ← 배치 이벤트 수신
POST /v1/events/beacon   ← sendBeacon (페이지 이탈)
GET  /v1/config          ← SDK 원격 설정 (샘플링률 등)
GET  /v1/health          ← 헬스체크
```

### API Gateway 타입: HTTP API

- REST API 대비 70% 저렴 ($1.00 vs $3.50 / 백만 요청)
- 지연 시간 더 낮음 (~10ms vs ~30ms)
- CORS, 스테이지 지원

### 인증 & 보안

- **인증:** 커스텀 헤더(`x-api-key`)를 Lambda Authorizer에서 검증. HTTP API는 Usage Plan을 지원하지 않으므로, Lambda Authorizer에서 API Key 유효성 + Rate Limit 판단.
- **Rate Limit:** Lambda Authorizer 내에서 DynamoDB 카운터 기반 1,000 req/s per key. 또는 WAF Rate-based Rule 활용.
- **Payload 제한:** 512KB
- **WAF:** Bot 탐지, IP 기반 제한
- **Origin 검증:** Web은 Referer/Origin 헤더 확인

### 핵심 최적화: Service Integration

API Gateway → Kinesis Firehose 직접 연결 (Service Integration).
이벤트 수신용 Lambda가 불필요하여 비용 절감 + 지연 감소 + 콜드 스타트 제거.

## 5. Layer ③ — Stream Processing (Firehose + Lambda)

### Kinesis Data Firehose

- **버퍼:** 5MB 또는 60초 (먼저 도달하는 조건)
- **출력:** S3 (Parquet 형식, 동적 파티셔닝)
- **실패 처리:** 변환 실패 레코드 → S3 errors/ 버킷

### Lambda Transform

- **런타임:** Python 3.12
- **메모리:** 256MB
- **타임아웃:** 60초
- **처리 내용:**
  1. 스키마 검증 (필수 필드 존재 여부)
  2. GeoIP Enrichment (MaxMind GeoLite2 DB → Lambda Layer)
  3. User-Agent Parsing (OS, 브라우저, 디바이스 추출)
  4. Session Stitching (session_id 기반 세션 연속성 보장)
  5. IP 주소 폐기 (GeoIP 변환 후)

### GeoIP DB 업데이트

- EventBridge 월 1회 스케줄 → Lambda가 MaxMind에서 최신 DB 다운로드 → Lambda Layer 버전 업데이트

## 6. Layer ④ — Storage (S3 Data Lake)

### 버킷 구조

```
s3://rum-data-lake/
├── raw/                          ← Firehose 출력
│   └── platform=web/
│       └── year=2026/
│           └── month=04/
│               └── day=01/
│                   └── hour=09/
│                       └── events-001.parquet
├── aggregated/                   ← 집계 Lambda 출력
│   ├── hourly/
│   │   └── metric=cwv/
│   │       └── 2026-04-01-09.parquet
│   └── daily/
│       └── metric=user_journey/
│           └── 2026-04-01.parquet
├── errors/                       ← Firehose 실패 레코드
└── config/                       ← SDK 원격 설정 JSON
```

### 파티셔닝: `platform / year / month / day / hour`

Parquet 컬럼형 포맷 + 파티셔닝으로 Athena 스캔 비용 최소화.
예: "오늘 Web의 LCP 평균" 쿼리 → 전체 데이터의 ~0.1%만 스캔.

### S3 Lifecycle Policy

| Prefix | 0~90일 | 90~365일 | 365일 후 |
|--------|--------|----------|----------|
| raw/ | S3 Standard | 삭제 | — |
| aggregated/ | S3 Standard | S3 IA | Glacier |
| errors/ | S3 Standard (30일 후 삭제) | — | — |

### 예상 용량 (DAU 5만)

- 일 이벤트: ~500만 건
- Parquet 일 용량: ~500MB (JSON 대비 ~80% 압축)
- 월 용량: ~15GB
- 90일 raw: ~45GB

### Glue Data Catalog 테이블

| 테이블 | 설명 | 소스 |
|--------|------|------|
| rum_events | Raw 이벤트 | Firehose 파티션 자동 등록 |
| rum_hourly_metrics | 시간별 집계 메트릭 | Aggregation Lambda |
| rum_daily_summary | 일별 요약 | Aggregation Lambda |

## 7. Layer ⑤ — Aggregation

### 스케줄

| 주기 | 트리거 | 집계 내용 |
|------|--------|-----------|
| 매시간 | EventBridge `cron(0 * * * ? *)` | CWV 백분위(p50/p75/p95/p99), 에러 수/에러율, 페이지별 로딩 시간, API 응답 시간, 활성 사용자 수 |
| 매일 01:00 | EventBridge `cron(0 1 * * ? *)` | DAU/WAU/MAU, 사용자 여정(Top 경로, 이탈 지점), 신규 vs 재방문, 디바이스/OS/브라우저 분포, 지역별 분포, 에러 Top 10 |
| 5분 간격 | EventBridge `rate(5 minutes)` | 에러 급증/성능 저하 감지 → SNS → Slack/Email |

### 집계 방식

Lambda가 Athena로 raw 테이블의 해당 시간 파티션을 쿼리 → 결과를 Parquet으로 S3 aggregated/ 에 저장.

## 8. Layer ⑥ — Dashboard & Alerting

### Grafana 배포

- **호스팅:** ECS Fargate (0.5 vCPU, 1GB RAM, 1 Task) — ~$30/월
- **대안:** Amazon Managed Grafana — $9/editor/월 (5명 이하 팀이면 더 경제적)
- **데이터 소스:** Amazon Athena Plugin
- **인증:** ALB + Cognito (SSO)

### 대시보드 (3개)

| 대시보드 | 주요 패널 | 데이터 소스 |
|----------|----------|-------------|
| **Core Web Vitals** | LCP/INP/CLS 현재값 + p75 게이지, 24h 트렌드, 페이지별 비교, 디바이스별 비교 | rum_hourly_metrics |
| **Error Monitoring** | JS/App 에러율, 에러 Top 10, 에러 트렌드, API 에러율 by 엔드포인트 | rum_hourly_metrics + rum_events (드릴다운) |
| **User Journey** | DAU/세션 수, 평균 세션 시간, Top 경로, 이탈 지점, 신규/재방문 비율, 지역/디바이스 분포 | rum_daily_summary |

### 알림 체계

| 채널 | 조건 | 알림 대상 |
|------|------|-----------|
| Lambda (5분) | JS 에러율 > 5%, API 에러율 > 10%, LCP p75 > 4s, 크래시율 > 1%, 이벤트 수신 급감 | SNS → Slack/Email |
| Grafana Alert | 트렌드 기반 (전일 대비 악화) | Slack/PagerDuty |
| CloudWatch Alarm | Firehose DeliveryToS3 실패, Lambda 에러율 | SNS → Ops 채널 |

## 9. Phase 2 — Session Replay (향후)

Phase 1 완료 후 확장 계획:

1. **Web:** rrweb SDK 통합 → DOM 변경 기반 영상 리플레이
2. **저장:** S3에 리플레이 데이터 별도 저장 (session_id로 연결)
3. **뷰어:** Grafana 패널 또는 별도 React 뷰어
4. **비용:** 리플레이 데이터는 샘플링(10~20%) 적용하여 비용 제어

## 10. IaC & 배포

- **IaC:** Terraform (기존 프로젝트 패턴과 일관성 유지)
- **CI/CD:** GitHub Actions → CDK Deploy
- **환경:** dev / staging / prod 분리
- **모니터링:** CloudWatch로 파이프라인 자체 헬스 모니터링

## 11. 구현 순서 (예상)

| Phase | 기간 | 범위 |
|-------|------|------|
| Phase 1a | 1~2주 | 인프라 (API GW, Firehose, S3, Glue, Athena) + IaC |
| Phase 1b | 1~2주 | Web SDK + 통합 테스트 |
| Phase 1c | 1주 | Grafana + 대시보드 + 알림 |
| Phase 1d | 1~2주 | Mobile SDK |
| Phase 1e | 1주 | Aggregation Lambda + 성능 튜닝 |
| **Phase 1 합계** | **5~8주** | |
| Phase 2 | 추후 | Session Replay |
