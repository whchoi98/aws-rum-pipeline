---
description: 전체 테스트 스위트 실행 (Lambda + SDK + iOS + Android + CDK)
allowed-tools: Read, Bash(python3:*), Bash(npm:*), Bash(npx:*), Bash(swift:*), Bash(cd:*), Glob
---

# Test All

프로젝트 전체 테스트 스위트를 실행합니다.

## Step 1: Lambda 테스트 (Python pytest)

각 Lambda 함수의 테스트를 실행:

```bash
cd lambda/authorizer && python3 -m pytest test_handler.py -v
cd lambda/ingest && python3 -m pytest test_handler.py -v
cd lambda/transform && python3 -m pytest test_handler.py -v
cd lambda/partition-repair && python3 -m pytest test_handler.py -v
cd lambda/athena-query && python3 -m pytest test_handler.py -v
```

## Step 2: SDK 테스트 (TypeScript vitest)

```bash
cd sdk && npm test
```

## Step 3: Simulator 테스트

```bash
cd simulator && npm test
```

## Step 4: iOS SDK 테스트 (Swift)

```bash
cd mobile-sdk-ios && swift test
```

## Step 5: Android SDK 테스트 (Kotlin)

```bash
cd mobile-sdk-android && ./gradlew :rum-sdk:test
```

## Step 6: CDK 합성 검증

```bash
cd cdk && npx cdk synth --quiet
```

## Step 7: 결과 보고

- 각 스위트별 통과/실패 수
- 실패한 테스트의 세부 정보 (파일 경로, 에러 메시지)
- 실패 원인이 명확한 경우 수정 제안
