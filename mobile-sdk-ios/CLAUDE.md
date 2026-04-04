<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## iOS RUM SDK Module

### Role
iOS용 RUM SDK (Swift, Swift Package Manager).
브라우저 SDK와 동일한 이벤트 스키마로 RUM 이벤트를 수집하여 API Gateway로 전송.

### Key Files
- `Sources/RumSDK/RumSDK.swift` — SDK 진입점. 초기화, 설정, 공개 API
- `Sources/RumSDK/collectors/` — 이벤트 수집기 (페이지뷰, 에러, 사용자 액션 등)
- `Sources/RumSDK/models/` — RUM 이벤트 데이터 모델 (Codable)
- `Tests/` — 단위 테스트 (Swift Testing / XCTest)
- `Package.swift` — SPM 패키지 정의 및 타겟 설정

### Key Commands
```bash
swift build            # SDK 빌드
swift test             # 테스트 실행
swift package resolve  # 의존성 해결
```

### Rules
- **최소 지원 버전**: iOS 15+
- **Swift 버전**: Swift 5.9+
- **외부 의존성 금지**: 표준 iOS/Swift 라이브러리만 사용 (Foundation, UIKit, SwiftUI)
- **스레드 안전성**: DispatchQueue를 사용한 스레드 안전 처리 필수
- 이벤트 스키마는 브라우저 SDK(`sdk/`) 및 Android SDK와 동일하게 유지
- 공개 API는 `@objc` 어노테이션으로 Objective-C 호환성 고려
- 네트워크 실패 시 재시도 로직 포함 (로컬 큐 버퍼링)

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## iOS RUM SDK Module

### Role
RUM SDK for iOS (Swift, Swift Package Manager).
Collects RUM events using the same event schema as the browser SDK and sends them to the API Gateway.

### Key Files
- `Sources/RumSDK/RumSDK.swift` — SDK entry point. Initialization, configuration, public API
- `Sources/RumSDK/collectors/` — Event collectors (page views, errors, user actions, etc.)
- `Sources/RumSDK/models/` — RUM event data models (Codable)
- `Tests/` — Unit tests (Swift Testing / XCTest)
- `Package.swift` — SPM package definition and target configuration

### Key Commands
```bash
swift build            # Build SDK
swift test             # Run tests
swift package resolve  # Resolve dependencies
```

### Rules
- **Minimum supported version**: iOS 15+
- **Swift version**: Swift 5.9+
- **No external dependencies**: Use only standard iOS/Swift libraries (Foundation, UIKit, SwiftUI)
- **Thread safety**: Thread-safe handling via DispatchQueue is required
- Event schema must stay consistent with the browser SDK (`sdk/`) and Android SDK
- Public APIs should include `@objc` annotation for Objective-C compatibility
- Includes retry logic on network failure (local queue buffering)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
