# Phase 1b — Web SDK + Simulator Design

**Date:** 2026-04-02
**Status:** Approved
**Depends on:** Phase 1a (infrastructure) + Phase 1a.5 (security)

## 1. Overview

브라우저 RUM 데이터를 수집하여 배포된 API 엔드포인트로 전송하는 경량 TypeScript SDK와 파이프라인 검증을 위한 Node.js 시뮬레이션 클라이언트.

### Goals

- 경량 SDK (<10KB gzip) — TypeScript, tree-shakeable
- Core Web Vitals (LCP, CLS, INP) + 에러 + 페이지뷰 + 리소스 수집
- 배치 전송 (30초/10개), 오프라인 큐잉, sendBeacon 페이지 이탈 처리
- npm 패키지 배포 (@myorg/rum-sdk)
- Node.js 시뮬레이터로 DAU 5,000 규모 테스트 트래픽 생성

### Non-Goals

- Mobile SDK (Phase 1d)
- 세션 리플레이 (Phase 2)
- CDN 호스팅 (npm 패키지로 충분)

## 2. SDK Architecture

```
@myorg/rum-sdk
├── src/
│   ├── index.ts          ← 진입점, RumSDK 클래스
│   ├── config.ts         ← SDK 설정 타입
│   ├── buffer.ts         ← EventBuffer (배치, 타이머, 큐)
│   ├── transport.ts      ← Transport (fetch, sendBeacon, gzip, 재시도)
│   ├── collectors/
│   │   ├── web-vitals.ts ← LCP, CLS, INP (web-vitals 라이브러리)
│   │   ├── error.ts      ← window.onerror, unhandledrejection
│   │   ├── navigation.ts ← 페이지뷰, SPA route (History API)
│   │   └── resource.ts   ← XHR/Fetch 래핑, 응답시간/상태
│   └── utils/
│       ├── id.ts         ← session_id, device_id 생성
│       └── context.ts    ← 브라우저/OS/URL 컨텍스트 수집
├── package.json
├── tsconfig.json
├── esbuild.config.js
└── tests/
    ├── buffer.test.ts
    ├── transport.test.ts
    └── collectors/
        ├── error.test.ts
        └── navigation.test.ts
```

## 3. SDK Public API

```typescript
interface RumConfig {
  endpoint: string;       // API Gateway URL
  apiKey: string;         // x-api-key 헤더 값
  appVersion: string;     // 앱 버전
  sampleRate?: number;    // 0-1, 기본 1.0
  flushInterval?: number; // ms, 기본 30000
  maxBatchSize?: number;  // 기본 10
  debug?: boolean;        // 콘솔 로깅
}

class RumSDK {
  static init(config: RumConfig): void;
  static destroy(): void;       // 수집 중단, 큐 flush
  static setUser(userId: string): void;
  static addCustomEvent(name: string, payload: object): void;
}
```

## 4. EventBuffer

- 이벤트 수신 → 내부 배열에 추가
- 배열 크기 >= maxBatchSize 또는 flushInterval 도달 시 Transport로 전송
- `visibilitychange` 이벤트 (hidden) 시 sendBeacon으로 즉시 flush
- flush 실패 시 이벤트를 다시 버퍼에 추가 (최대 500개, 초과 시 오래된 것 삭제)

## 5. Transport

- **Primary:** `fetch` POST → `{endpoint}/v1/events`
  - Headers: `Content-Type: application/json`, `x-api-key: {apiKey}`
  - Body: JSON 배열
- **Fallback:** `navigator.sendBeacon` (페이지 이탈 시)
  - Blob으로 래핑
- **재시도:** 네트워크 에러 또는 5xx 시 exponential backoff (1s, 2s, 4s), 최대 3회
- **오프라인:** `navigator.onLine === false` → 전송 대기, `online` 이벤트 시 flush

## 6. Collectors

### 6.1 WebVitalsCollector
- `web-vitals` 라이브러리 사용 (Google, ~1.5KB gzip)
- `onLCP`, `onCLS`, `onINP` 콜백 등록
- event_type: "performance", event_name: "lcp" | "cls" | "inp"
- payload: { value, rating, navigationType }

### 6.2 ErrorCollector
- `window.addEventListener('error', ...)` — JS 에러
- `window.addEventListener('unhandledrejection', ...)` — 프로미스 에러
- event_type: "error", event_name: "js_error" | "unhandled_rejection"
- payload: { message, stack (최대 1000자), filename, lineno, colno }
- 자기 자신(SDK) 에러는 무시

### 6.3 NavigationCollector
- `PerformanceObserver` (type: "navigation") — 초기 로딩 메트릭
- History API 래핑 (pushState, replaceState, popstate) — SPA 라우트 변경
- event_type: "navigation", event_name: "page_view" | "route_change"
- payload: { url, referrer, duration }

### 6.4 ResourceCollector
- `PerformanceObserver` (type: "resource") — XHR/Fetch 리소스
- initiatorType: "xmlhttprequest" | "fetch" 만 수집 (이미지/CSS 제외)
- event_type: "resource", event_name: "xhr" | "fetch"
- payload: { url, method, status, duration, transferSize }

## 7. Event Schema

원본 설계 스펙(Section 3.3)의 통합 이벤트 스키마를 그대로 사용:

```json
{
  "session_id": "uuid",
  "user_id": "hashed_id | anonymous",
  "device_id": "uuid",
  "timestamp": 1712000000000,
  "platform": "web",
  "app_version": "2.1.0",
  "event_type": "performance | action | error | navigation | resource",
  "event_name": "lcp | click | js_error | page_view | xhr",
  "payload": {},
  "context": {
    "url": "/products/123",
    "device": { "os": "macOS", "browser": "Chrome 120" },
    "connection": { "type": "4g", "rtt": 50 }
  }
}
```

## 8. Build & Package

- **빌드:** esbuild
  - ESM: `dist/index.mjs` (tree-shaking 지원)
  - CJS: `dist/index.cjs`
  - IIFE: `dist/rum-sdk.min.js` (CDN/script 태그용)
- **번들 크기 목표:** <10KB gzip (IIFE)
- **package.json exports:** `main` (CJS), `module` (ESM), `browser` (IIFE)
- **TypeScript:** strict mode, 타입 선언 포함 (`dist/index.d.ts`)

## 9. Simulator

### 9.1 Architecture

```
simulator/
├── src/
│   ├── index.ts          ← 메인 루프
│   ├── generator.ts      ← 이벤트 생성기
│   ├── scenarios.ts      ← 시나리오 정의 (정상, 느린, 에러급증)
│   └── session.ts        ← 세션/유저 생성
├── Dockerfile
├── k8s/
│   └── cronjob.yaml      ← EKS CronJob (5분 간격)
├── package.json
└── tsconfig.json
```

### 9.2 Event Distribution

| 이벤트 타입 | 비율 | 세부 |
|-------------|------|------|
| performance (CWV) | 30% | LCP: good 70%, needs-improvement 20%, poor 10% |
| navigation | 25% | page_view 80%, route_change 20% |
| resource | 25% | fetch 60%, xhr 40%, 4xx 5%, 5xx 2% |
| error | 10% | js_error 70%, unhandled_rejection 30% |
| action | 10% | click 80%, scroll 20% |

### 9.3 Configuration

환경 변수:

| 변수 | 기본값 | 설명 |
|------|--------|------|
| RUM_API_ENDPOINT | (필수) | API Gateway URL |
| RUM_API_KEY | (필수) | API Key |
| EVENTS_PER_BATCH | 100 | 배치당 이벤트 수 |
| CONCURRENT_SESSIONS | 10 | 동시 세션 수 |
| INTERVAL_SECONDS | 300 | 실행 간격 (초) |

### 9.4 Deployment

**EKS CronJob:**
```yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  name: rum-simulator
spec:
  schedule: "*/5 * * * *"
  jobTemplate:
    spec:
      template:
        spec:
          containers:
          - name: simulator
            image: {ECR_REPO}/rum-simulator:latest
            env:
            - name: RUM_API_ENDPOINT
              value: "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com"
            - name: RUM_API_KEY
              valueFrom:
                secretKeyRef:
                  name: rum-api-key
                  key: api-key
          restartPolicy: OnFailure
```

**대안:** EC2에서 cron + Docker로 실행 가능.

## 10. Testing

### SDK 단위 테스트 (vitest)
- EventBuffer: 배치 크기, 타이머, flush, 오버플로우
- Transport: fetch 성공/실패, 재시도, sendBeacon fallback
- ErrorCollector: 에러 캡처, 스택 트리밍, 자기 에러 무시
- NavigationCollector: 페이지뷰 감지, SPA 라우트 변경

### 통합 테스트
- SDK init → 이벤트 수집 → API 전송 → 200 응답 확인
- 시뮬레이터 실행 → S3에 데이터 도착 확인

## 11. Implementation Order

1. SDK 코어 (buffer, transport, config) + 단위 테스트
2. Collectors (web-vitals, error, navigation, resource) + 테스트
3. 빌드 설정 (esbuild, package.json)
4. 시뮬레이터 (generator, scenarios, Docker, k8s)
5. 통합 테스트
