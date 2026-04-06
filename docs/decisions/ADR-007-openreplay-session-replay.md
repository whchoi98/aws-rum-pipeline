<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

# ADR-007: OpenReplay 세션 리플레이

## Status
Accepted

## Context
RUM 이벤트 수집(페이지뷰, 에러, Core Web Vitals)은 구현되었으나 세션 리플레이(DOM 녹화/재생) 기능이 없음.
사용자가 실제로 어떤 경험을 했는지 시각적으로 재현할 수 없어 디버깅과 UX 분석에 한계가 있음.

선택지:
1. **rrweb 자체 구현** — DOM 녹화 라이브러리를 직접 통합하고 재생 UI 구축
2. **OpenReplay 셀프호스팅** — 오픈소스 세션 리플레이 플랫폼을 자체 인프라에 배포
3. **상용 SaaS** (FullStory, LogRocket 등) — 외부 서비스 구독

## Decision
- **OpenReplay 셀프호스팅** (Docker Compose on EC2) 채택
- 기존 RUM SDK와 병행 운영 (OpenReplay 트래커를 별도 설치)
- CF → CF Prefix List SG → ALB → EC2 패턴 (기존 Agent UI와 동일한 아키텍처)
- RDS PostgreSQL, ElastiCache Redis, S3를 외부 관리형 서비스로 사용 (데이터 내구성)
- Cognito SSO 재사용 — Lambda@Edge JWT 검증으로 대시보드 접근 제어
- `/ingest/*` 경로는 인증 없음 (트래커 SDK에서 세션 데이터 전송)
- 독립 Terraform 모듈 (`terraform/modules/openreplay/`) + CDK Construct (`cdk/lib/constructs/openreplay.ts`)

## Consequences
- **장점**:
  - 즉시 사용 가능한 세션 리플레이 + DevTools (네트워크, 콘솔, 성능)
  - 오픈소스 (라이선스 비용 없음), 데이터가 자체 인프라에 저장
  - 기존 RUM 파이프라인에 영향 없음 (독립 모듈)
- **단점**:
  - ~$210/월 추가 비용 (EC2 m7g.xlarge + RDS + ElastiCache + S3)
  - Docker Compose 기반 운영 (EC2 패치, 디스크 모니터링 필요)
  - OpenReplay 버전 업그레이드 시 수동 작업 (git pull + docker compose up)

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

# ADR-007: OpenReplay Session Replay

## Status
Accepted

## Context
RUM event collection (page views, errors, Core Web Vitals) was implemented, but session replay (DOM recording/playback) capability was missing.
Without the ability to visually reproduce actual user experiences, debugging and UX analysis remained limited.

Options:
1. **Custom rrweb implementation** — Directly integrate the DOM recording library and build a playback UI
2. **Self-hosted OpenReplay** — Deploy an open-source session replay platform on own infrastructure
3. **Commercial SaaS** (FullStory, LogRocket, etc.) — Subscribe to an external service

## Decision
- Adopt **self-hosted OpenReplay** (Docker Compose on EC2)
- Operate in parallel with the existing RUM SDK (OpenReplay tracker installed separately)
- CF → CF Prefix List SG → ALB → EC2 pattern (same architecture as Agent UI)
- Use RDS PostgreSQL, ElastiCache Redis, S3 as external managed services (data durability)
- Reuse Cognito SSO — Lambda@Edge JWT validation for dashboard access control
- `/ingest/*` path has no authentication (tracker SDK sends session data)
- Independent Terraform module (`terraform/modules/openreplay/`) + CDK Construct (`cdk/lib/constructs/openreplay.ts`)

## Consequences
- **Pros**:
  - Ready-to-use session replay + DevTools (network, console, performance)
  - Open source (no license cost), data stored on own infrastructure
  - No impact on existing RUM pipeline (independent module)
- **Cons**:
  - ~$210/month additional cost (EC2 m7g.xlarge + RDS + ElastiCache + S3)
  - Docker Compose-based operations (EC2 patching, disk monitoring required)
  - Manual work for OpenReplay version upgrades (git pull + docker compose up)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
