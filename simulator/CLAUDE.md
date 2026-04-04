<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Simulator Module

### Role
실제 브라우저 SDK를 호출하는 RUM 트래픽 생성기.
부하 테스트, 파이프라인 검증, 개발 환경 데이터 시딩에 사용.
Docker 컨테이너로 실행 가능.

### Key Files
- `src/` — 시뮬레이터 소스 (TypeScript)
- `tests/` — vitest 테스트
- `k8s/` — EKS 배포 설정 (CronJob YAML 포함)
  - `k8s/cronjob.yaml` — EKS CronJob (5분 주기 트래픽 생성)
- `Dockerfile` — 컨테이너 이미지 빌드
- `package.json` — 의존성 및 스크립트
- `tsconfig.json` — TypeScript 설정

### Key Commands
```bash
npm install                          # 의존성 설치
npm test                             # vitest 실행
docker build -t rum-simulator .      # 이미지 빌드

# 실행 예시
RUM_API_ENDPOINT=https://<api-id>.execute-api.ap-northeast-2.amazonaws.com \
RUM_API_KEY=<key> \
EVENTS_PER_BATCH=50 \
CONCURRENT_SESSIONS=5 \
npx tsx src/index.ts
```

### Rules
- `RUM_API_ENDPOINT`, `RUM_API_KEY` 환경변수 필수
- 실제 SDK와 동일한 이벤트 스키마 사용
- 동시 세션 수 (`CONCURRENT_SESSIONS`) 조절 가능
- 프로덕션 엔드포인트 직접 사용 주의

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Simulator Module

### Role
A RUM traffic generator that invokes the actual browser SDK.
Used for load testing, pipeline validation, and development environment data seeding.
Can be run as a Docker container.

### Key Files
- `src/` — Simulator source (TypeScript)
- `tests/` — vitest tests
- `k8s/` — EKS deployment configuration (includes CronJob YAML)
  - `k8s/cronjob.yaml` — EKS CronJob (traffic generation every 5 minutes)
- `Dockerfile` — Container image build
- `package.json` — Dependencies and scripts
- `tsconfig.json` — TypeScript configuration

### Key Commands
```bash
npm install                          # Install dependencies
npm test                             # Run vitest
docker build -t rum-simulator .      # Build image

# Run example
RUM_API_ENDPOINT=https://<api-id>.execute-api.ap-northeast-2.amazonaws.com \
RUM_API_KEY=<key> \
EVENTS_PER_BATCH=50 \
CONCURRENT_SESSIONS=5 \
npx tsx src/index.ts
```

### Rules
- `RUM_API_ENDPOINT`, `RUM_API_KEY` environment variables are required
- Uses the same event schema as the actual SDK
- Concurrent sessions (`CONCURRENT_SESSIONS`) are configurable
- Use caution when targeting production endpoints directly

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
