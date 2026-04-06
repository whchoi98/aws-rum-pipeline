<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: SDK 릴리스 조율 (Web / iOS / Android)

### 개요
Web, iOS, Android 세 플랫폼의 RUM SDK를 릴리스하는 절차.
이벤트 스키마 호환성 확인, 테스트, 빌드, 버전 태깅, 배포를 다룬다.

### 사전 조건
- Node.js >= 18 (Web SDK 빌드)
- Xcode >= 15 / Swift 5.9+ (iOS SDK)
- JDK 17+ / Android SDK (Android SDK)
- npm 레지스트리 publish 권한 (Web)
- GitHub 태그 push 권한

### 절차

#### 1. 이벤트 스키마 호환성 확인

```bash
# 세 SDK가 동일한 이벤트 스키마를 생성하는지 확인
# Web SDK 스키마
cat sdk/src/types.ts | grep -A 20 "interface RumEvent"

# iOS SDK 스키마
cat mobile-sdk-ios/Sources/RumSdk/Models/RumEvent.swift | grep -A 20 "struct RumEvent"

# Android SDK 스키마
cat mobile-sdk-android/rum-sdk/src/main/kotlin/com/example/rumsdk/models/RumEvent.kt | grep -A 20 "data class RumEvent"

# Glue 테이블 스키마와 일치하는지 교차 확인
aws glue get-table \
  --database-name rum_pipeline_db \
  --name rum_events \
  --query 'Table.StorageDescriptor.Columns[].{Name:Name,Type:Type}' \
  --output table
```

#### 2. 전체 SDK 테스트 실행

```bash
# Web SDK
cd sdk && npm ci && npm test
echo "Web SDK 테스트 완료: $?"

# iOS SDK
cd mobile-sdk-ios && swift build && swift test
echo "iOS SDK 테스트 완료: $?"

# Android SDK
cd mobile-sdk-android && ./gradlew :rum-sdk:test
echo "Android SDK 테스트 완료: $?"
```

#### 3. 시뮬레이터로 파이프라인 호환성 검증

```bash
# 시뮬레이터 빌드 및 E2E 테스트
cd simulator && npm ci && npm test

# 실제 파이프라인에 테스트 이벤트 전송
bash scripts/test-ingestion.sh \
  "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com" \
  "<test-api-key>"
```

#### 4. 버전 범프

```bash
# Semver 전략: 각 SDK는 독립 버전 관리
# 하위 호환 변경: patch (1.0.x)
# 새 기능 추가: minor (1.x.0)
# 호환성 깨짐: major (x.0.0)

# Web SDK
cd sdk && npm version patch  # 또는 minor / major

# iOS SDK — Package.swift 또는 태그 기반
# Android SDK — build.gradle.kts 내 version 수정
```

#### 5. 빌드 아티팩트 생성

```bash
# Web SDK — npm 패키지
cd sdk && npm run build
npm pack  # .tgz 생성 확인

# iOS SDK — SPM 태그 (빌드 확인)
cd mobile-sdk-ios && swift build -c release

# Android SDK — AAR 빌드
cd mobile-sdk-android && ./gradlew :rum-sdk:assembleRelease
```

#### 6. CHANGELOG 및 태그

```bash
# CHANGELOG.md 업데이트 (Keep a Changelog 형식)
# [x.y.z] - 2026-04-06 섹션 추가

# Git 태그 생성
git add -A && git commit -m "release: SDK vX.Y.Z"
git tag -a sdk-web-v1.x.x -m "Web SDK release v1.x.x"
git tag -a sdk-ios-v1.x.x -m "iOS SDK release v1.x.x"
git tag -a sdk-android-v1.x.x -m "Android SDK release v1.x.x"
git push origin --tags
```

#### 7. 배포

```bash
# Web SDK — npm publish
cd sdk && npm publish

# iOS SDK — GitHub 태그가 SPM에서 자동으로 사용 가능
# Android SDK — Maven/Gradle publish (설정에 따라)
cd mobile-sdk-android && ./gradlew :rum-sdk:publish
```

### 롤백

```bash
# npm unpublish (24시간 이내만 가능)
npm unpublish @rum-pipeline/sdk@1.x.x

# Git 태그 삭제
git tag -d sdk-web-v1.x.x
git push origin --delete sdk-web-v1.x.x
```

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: SDK Release Coordination (Web / iOS / Android)

### Overview
Procedure for releasing RUM SDKs across Web, iOS, and Android platforms.
Covers event schema compatibility, testing, building, version tagging, and deployment.

### Prerequisites
- Node.js >= 18 (Web SDK build)
- Xcode >= 15 / Swift 5.9+ (iOS SDK)
- JDK 17+ / Android SDK (Android SDK)
- npm registry publish permissions (Web)
- GitHub tag push permissions

### Procedure

#### 1. Verify Event Schema Compatibility

```bash
# Verify all three SDKs produce the same event schema
# Web SDK schema
cat sdk/src/types.ts | grep -A 20 "interface RumEvent"

# iOS SDK schema
cat mobile-sdk-ios/Sources/RumSdk/Models/RumEvent.swift | grep -A 20 "struct RumEvent"

# Android SDK schema
cat mobile-sdk-android/rum-sdk/src/main/kotlin/com/example/rumsdk/models/RumEvent.kt | grep -A 20 "data class RumEvent"

# Cross-check against Glue table schema
aws glue get-table \
  --database-name rum_pipeline_db \
  --name rum_events \
  --query 'Table.StorageDescriptor.Columns[].{Name:Name,Type:Type}' \
  --output table
```

#### 2. Run All SDK Tests

```bash
# Web SDK
cd sdk && npm ci && npm test
echo "Web SDK tests complete: $?"

# iOS SDK
cd mobile-sdk-ios && swift build && swift test
echo "iOS SDK tests complete: $?"

# Android SDK
cd mobile-sdk-android && ./gradlew :rum-sdk:test
echo "Android SDK tests complete: $?"
```

#### 3. Verify Pipeline Compatibility with Simulator

```bash
# Build simulator and run E2E tests
cd simulator && npm ci && npm test

# Send test events to actual pipeline
bash scripts/test-ingestion.sh \
  "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com" \
  "<test-api-key>"
```

#### 4. Version Bump

```bash
# Semver strategy: each SDK has independent versioning
# Backwards-compatible fix: patch (1.0.x)
# New feature: minor (1.x.0)
# Breaking change: major (x.0.0)

# Web SDK
cd sdk && npm version patch  # or minor / major

# iOS SDK — based on Package.swift or git tags
# Android SDK — update version in build.gradle.kts
```

#### 5. Build Artifacts

```bash
# Web SDK — npm package
cd sdk && npm run build
npm pack  # verify .tgz is generated

# iOS SDK — SPM tag (verify build)
cd mobile-sdk-ios && swift build -c release

# Android SDK — AAR build
cd mobile-sdk-android && ./gradlew :rum-sdk:assembleRelease
```

#### 6. CHANGELOG and Tags

```bash
# Update CHANGELOG.md (Keep a Changelog format)
# Add [x.y.z] - 2026-04-06 section

# Create git tags
git add -A && git commit -m "release: SDK vX.Y.Z"
git tag -a sdk-web-v1.x.x -m "Web SDK release v1.x.x"
git tag -a sdk-ios-v1.x.x -m "iOS SDK release v1.x.x"
git tag -a sdk-android-v1.x.x -m "Android SDK release v1.x.x"
git push origin --tags
```

#### 7. Publish

```bash
# Web SDK — npm publish
cd sdk && npm publish

# iOS SDK — GitHub tag is automatically available via SPM
# Android SDK — Maven/Gradle publish (depending on config)
cd mobile-sdk-android && ./gradlew :rum-sdk:publish
```

### Rollback

```bash
# npm unpublish (only within 24 hours)
npm unpublish @rum-pipeline/sdk@1.x.x

# Delete git tags
git tag -d sdk-web-v1.x.x
git push origin --delete sdk-web-v1.x.x
```

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
