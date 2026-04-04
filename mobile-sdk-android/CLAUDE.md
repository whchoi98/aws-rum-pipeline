<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Android RUM SDK Module

### Role
Android용 RUM SDK (Kotlin, Gradle).
브라우저 SDK와 동일한 이벤트 스키마로 RUM 이벤트를 수집하여 API Gateway로 전송.

### Key Files
- `rum-sdk/src/main/kotlin/com/myorg/rum/RumSDK.kt` — SDK 진입점. 초기화, 설정, 공개 API
- `rum-sdk/src/main/kotlin/com/myorg/rum/collectors/` — 이벤트 수집기 (화면뷰, 에러, 사용자 액션 등)
- `rum-sdk/src/main/kotlin/com/myorg/rum/models/` — RUM 이벤트 데이터 모델 (data class + kotlinx.serialization)
- `rum-sdk/src/test/` — 단위 테스트 (JUnit5 + MockK)
- `build.gradle.kts` — Gradle 빌드 설정

### Key Commands
```bash
./gradlew :rum-sdk:build   # SDK 빌드
./gradlew :rum-sdk:test    # 테스트 실행
./gradlew :rum-sdk:lint    # 린트 검사
```

### Rules
- **최소 지원 버전**: minSdk 26 (Android 8.0+)
- **Kotlin 버전**: Kotlin 1.9+
- **외부 의존성 금지**: 표준 Android API만 사용 (android.*, java.net.*)
- **스레드 안전성**: `synchronized` 블록 + Kotlin Coroutines (`Dispatchers.IO`) 사용
- 이벤트 스키마는 브라우저 SDK(`sdk/`) 및 iOS SDK와 동일하게 유지
- 네트워크 실패 시 재시도 로직 포함 (Room DB 또는 SharedPreferences 큐 버퍼링)
- ProGuard/R8 규칙 포함 (`consumer-rules.pro`)

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Android RUM SDK Module

### Role
RUM SDK for Android (Kotlin, Gradle).
Collects RUM events using the same event schema as the browser SDK and sends them to the API Gateway.

### Key Files
- `rum-sdk/src/main/kotlin/com/myorg/rum/RumSDK.kt` — SDK entry point. Initialization, configuration, public API
- `rum-sdk/src/main/kotlin/com/myorg/rum/collectors/` — Event collectors (screen views, errors, user actions, etc.)
- `rum-sdk/src/main/kotlin/com/myorg/rum/models/` — RUM event data models (data class + kotlinx.serialization)
- `rum-sdk/src/test/` — Unit tests (JUnit5 + MockK)
- `build.gradle.kts` — Gradle build configuration

### Key Commands
```bash
./gradlew :rum-sdk:build   # Build SDK
./gradlew :rum-sdk:test    # Run tests
./gradlew :rum-sdk:lint    # Run lint checks
```

### Rules
- **Minimum supported version**: minSdk 26 (Android 8.0+)
- **Kotlin version**: Kotlin 1.9+
- **No external dependencies**: Use only standard Android APIs (android.*, java.net.*)
- **Thread safety**: Use `synchronized` blocks + Kotlin Coroutines (`Dispatchers.IO`)
- Event schema must stay consistent with the browser SDK (`sdk/`) and iOS SDK
- Includes retry logic on network failure (Room DB or SharedPreferences queue buffering)
- ProGuard/R8 rules included (`consumer-rules.pro`)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
