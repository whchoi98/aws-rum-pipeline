<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

# ADR-004: Mobile SDK 멀티플랫폼 지원 (iOS + Android)

## Status
Accepted

## Context
RUM 파이프라인이 초기에는 브라우저(TypeScript) SDK만 제공했으나, 네이티브 모바일 앱 커버리지를 위해
별도의 iOS 및 Android SDK가 필요함.
React Native/Flutter 하이브리드 접근 vs 네이티브 플랫폼 SDK 중 선택이 필요했으며,
기존 브라우저 SDK와 동일한 이벤트 스키마를 유지하여 파이프라인 통합이 핵심 요구사항.

## Decision
- 네이티브 플랫폼 SDK 채택 (iOS: Swift 5.9+/SPM, Android: Kotlin 1.9+/Gradle)
- 브라우저 SDK와 동일한 이벤트 스키마를 공유하여 Firehose/Glue 파이프라인 단일화
- 외부 의존성 제로 제약 — 표준 플랫폼 API만 사용
- iOS: iOS 15+, DispatchQueue 기반 스레드 안전성, URLSession 네트워킹
- Android: minSdk 26, Kotlin Coroutines 기반 스레드 안전성, HttpURLConnection 네트워킹
- 네트워크 실패 시 로컬 큐 버퍼링 + 지수 백오프 재시도
- 대안: React Native/Flutter 래퍼 SDK (단일 코드베이스) — 네이티브 API 접근 제한 및 성능 오버헤드로 기각

## Consequences
- **장점**: 플랫폼별 최적화된 성능, 네이티브 API 직접 접근, 외부 의존성 없어 앱 크기 최소화, 통합 이벤트 스키마로 파이프라인 단일 유지
- **단점**: 두 플랫폼 코드베이스 독립 유지보수 필요, 기능 패리티 동기화 부담, 테스트 매트릭스 증가

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

# ADR-004: Mobile SDK Multi-Platform Support (iOS + Android)

## Status
Accepted

## Context
The RUM pipeline initially provided only a browser (TypeScript) SDK. Dedicated iOS and Android SDKs
were needed for native mobile app coverage.
A choice between React Native/Flutter hybrid vs native platform SDKs was required,
with shared event schema across the browser SDK as a key requirement for unified pipeline integration.

## Decision
- Adopt native platform SDKs (iOS: Swift 5.9+/SPM, Android: Kotlin 1.9+/Gradle)
- Share the same event schema with the browser SDK for unified Firehose/Glue pipeline
- Zero external dependencies constraint — only standard platform APIs
- iOS: iOS 15+, DispatchQueue-based thread safety, URLSession networking
- Android: minSdk 26, Kotlin Coroutines-based thread safety, HttpURLConnection networking
- Local queue buffering with exponential backoff retry on network failure
- Alternative rejected: React Native/Flutter wrapper SDK (single codebase) — limited native API access and performance overhead

## Consequences
- **Pros**: Platform-optimized performance, direct native API access, minimal app size with no external dependencies, unified event schema keeps a single pipeline
- **Cons**: Independent maintenance of two platform codebases, feature parity synchronization overhead, increased test matrix

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
