<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

# ADR-003: Grafana 프리미엄 대시보드 (43패널) + KST 타임존

## Status
Accepted

## Context
기존 Grafana 대시보드는 6개 섹션 17개 패널로 기본 지표만 제공하여,
관리자 관점에서 트래픽 추이, 에러 영향 범위, 모바일 바이탈, 세션 탐색 등 핵심 지표가 부족했음.
또한 Athena의 `current_date`가 UTC 기준이라 KST 오전 9시 이전에 데이터가 0으로 표시되는 문제가 있었음.

## Decision
- 9개 섹션 43개 패널의 프리미엄 관리자 대시보드로 교체 (deploy-unified-dashboard.py)
- 날짜 필터를 `current_date` → `date(current_timestamp AT TIME ZONE 'Asia/Seoul')`로 변경
- 전수 수집 (샘플링 없음) 방식 유지

## Consequences
- **장점**: 관리자 관점의 종합적 모니터링, KST 기준 정확한 날짜 필터, Datadog RUM 수준의 가시성
- **단점**: 패널 수 증가로 Athena 쿼리 비용 소폭 증가 (Parquet + 파티션 프루닝으로 최소화)
- **완화**: Grafana 5분 자동 새로고침, Athena 워크그룹 100GB 스캔 제한

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

---

# 🇺🇸 English

# ADR-003: Grafana Premium Dashboard (43 Panels) + KST Timezone

## Status
Accepted

## Context
The existing Grafana dashboard had only 6 sections with 17 panels providing basic metrics,
lacking key insights for administrators such as traffic trends, error impact scope, mobile vitals, and session exploration.
Additionally, Athena's `current_date` is UTC-based, causing data to display as 0 before 9AM KST.

## Decision
- Replace with a premium admin dashboard containing 43 panels across 9 sections (deploy-unified-dashboard.py)
- Change date filters from `current_date` to `date(current_timestamp AT TIME ZONE 'Asia/Seoul')`
- Maintain full collection (no sampling) approach

## Consequences
- **Pros**: Comprehensive admin monitoring, accurate KST-based date filters, Datadog RUM-level visibility
- **Cons**: Increased panel count slightly raises Athena query costs (minimized with Parquet + partition pruning)
- **Mitigation**: Grafana 5-minute auto-refresh, Athena workgroup 100GB scan limit

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
