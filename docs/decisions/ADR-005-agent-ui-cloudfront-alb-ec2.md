<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

# ADR-005: Agent UI 호스팅 — CloudFront + ALB + EC2

## Status
Accepted

## Context
AgentCore Web UI (Next.js 14)의 호스팅 솔루션이 필요함.
에이전트 채팅이 Server-Sent Events(SSE)를 사용하며 세션이 수 분간 지속되므로,
Lambda의 30초 타임아웃은 스트리밍 채팅과 호환 불가.
ECS Fargate는 콜드 스타트 오버헤드가 있고, Next.js SSR + 스트리밍에는 장기 실행 서버가 필요.

## Decision
- CloudFront → ALB → EC2 (t4g.large ARM64) 아키텍처 채택
- t4g.large (ARM64)는 상시 가동 워크로드에 비용 효율적
- CloudFront로 정적 자산 엣지 캐싱 + Lambda@Edge 인증 (ADR-002)
- ALB 보안 그룹을 CloudFront 전용으로 제한하여 직접 접근 차단
- Next.js SSR + SSE 스트리밍을 위한 장기 실행 서버 프로세스 보장
- 대안 1: ECS Fargate + ALB — 콜드 스타트 오버헤드, 상시 가동 시 EC2 대비 비용 불리
- 대안 2: Lambda@Edge SSR — SSE 장시간 연결 불가 (30초 타임아웃)

## Consequences
- **장점**: SSE 장시간 스트리밍 지원, 일관된 저지연 응답, ARM64 비용 효율, CloudFront 엣지 캐싱 + 인증 통합
- **단점**: EC2 인스턴스 직접 관리 필요 (패치, 스케일링), 단일 인스턴스 장애 시 수동 복구, 컨테이너 대비 배포 자동화 복잡

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

# ADR-005: Agent UI Hosting — CloudFront + ALB + EC2

## Status
Accepted

## Context
A hosting solution was needed for the AgentCore Web UI (Next.js 14).
Agent chat uses Server-Sent Events (SSE) with sessions lasting several minutes,
making Lambda's 30-second timeout incompatible with streaming chat.
ECS Fargate has cold start overhead, and Next.js SSR with streaming requires a long-lived server.

## Decision
- Adopt CloudFront → ALB → EC2 (t4g.large ARM64) architecture
- t4g.large (ARM64) is cost-effective for always-on workloads
- CloudFront for static asset edge caching + Lambda@Edge authentication (ADR-002)
- ALB security group restricted to CloudFront-only to block direct access
- Long-lived server process to support Next.js SSR + SSE streaming
- Alternative 1: ECS Fargate + ALB — cold start overhead, higher cost than EC2 for always-on
- Alternative 2: Lambda@Edge SSR — cannot support long-lived SSE connections (30s timeout)

## Consequences
- **Pros**: Long-lived SSE streaming support, consistent low-latency responses, ARM64 cost efficiency, CloudFront edge caching + authentication integration
- **Cons**: Direct EC2 instance management required (patching, scaling), manual recovery on single-instance failure, more complex deployment automation compared to containers

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
