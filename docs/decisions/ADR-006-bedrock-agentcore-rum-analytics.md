<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

# ADR-006: Bedrock AgentCore 기반 RUM 분석 에이전트

## Status
Accepted

## Context
RUM 파이프라인에 Athena를 통해 RUM 데이터를 쿼리하고 자연어로 분석 결과를 제공하는
AI 기반 분석 에이전트가 필요함.
에이전트 프레임워크 선택 (Bedrock AgentCore vs LangChain vs 커스텀), 도구 통합 방식,
사용자별 대화 메모리 격리가 핵심 결정 사항.

## Decision
- Bedrock AgentCore (Runtime + Gateway + Memory) 채택
- Strands Agents SDK로 에이전트 로직 구현
- MCP (Model Context Protocol)로 도구 통합 — Athena 쿼리 Lambda를 MCP 도구로 Gateway에 등록
- Cognito `sub` 클레임 기반 사용자별 메모리 격리 (AgentCore Memory)
- Claude Sonnet을 파운데이션 모델로 사용
- 대안 1: LangChain + 자체 호스팅 — 인프라 관리 부담, 메모리/게이트웨이 직접 구현 필요
- 대안 2: Amazon Bedrock Agents (관리형) — MCP 도구 통합 유연성 부족, 커스텀 메모리 제어 제한

## Consequences
- **장점**: AWS 관리형 런타임으로 운영 부담 최소, MCP 기반 도구 확장 용이, 사용자별 메모리 격리 내장, Strands SDK의 간결한 에이전트 정의
- **단점**: AgentCore 서비스 종속 (AWS Lock-in), AgentCore 신규 서비스로 성숙도 리스크, Strands SDK 생태계 초기 단계

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

# ADR-006: Bedrock AgentCore for RUM Analytics

## Status
Accepted

## Context
The RUM pipeline needed an AI-powered analytics agent that queries RUM data via Athena
and provides natural language analysis.
Key decisions included the agent framework choice (Bedrock AgentCore vs LangChain vs custom),
tool integration approach, and per-user conversation memory isolation.

## Decision
- Adopt Bedrock AgentCore (Runtime + Gateway + Memory)
- Implement agent logic with Strands Agents SDK
- Use MCP (Model Context Protocol) for tool integration — register Athena query Lambda as an MCP tool via Gateway
- Per-user memory isolation based on Cognito `sub` claim (AgentCore Memory)
- Claude Sonnet as the foundation model
- Alternative 1: LangChain + self-hosting — infrastructure management burden, memory/gateway must be built from scratch
- Alternative 2: Amazon Bedrock Agents (managed) — limited MCP tool integration flexibility, restricted custom memory control

## Consequences
- **Pros**: Minimal operational overhead with AWS-managed runtime, easy tool extensibility via MCP, built-in per-user memory isolation, concise agent definition with Strands SDK
- **Cons**: AgentCore service dependency (AWS lock-in), maturity risk as a newer AWS service, early-stage Strands SDK ecosystem

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
