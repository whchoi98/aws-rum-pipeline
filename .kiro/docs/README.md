# 프로젝트 문서 가이드

## 문서 구조

```
docs/
├── architecture.md          # 전체 시스템 아키텍처 (이중 언어)
├── api-reference.md         # API 엔드포인트 레퍼런스
├── onboarding.md            # 개발자 온보딩 가이드
├── decisions/               # Architecture Decision Records (ADR)
│   ├── .template.md         # ADR 템플릿
│   ├── ADR-001-*.md         # Terraform + CDK 듀얼 IaC
│   ├── ADR-002-*.md         # Cognito SSO + Lambda@Edge
│   ├── ADR-003-*.md         # Grafana Premium Dashboard KST
│   ├── ADR-004-*.md         # Mobile SDK Multi-Platform
│   ├── ADR-005-*.md         # Agent UI CloudFront ALB EC2
│   ├── ADR-006-*.md         # Bedrock AgentCore RUM Analytics
│   └── ADR-007-*.md         # OpenReplay Session Replay
├── runbooks/                # 운영 런북 (01~14)
│   └── .template.md         # 런북 템플릿
└── superpowers/             # 설계 스펙 및 구현 계획
    ├── specs/               # 설계 문서
    └── plans/               # 구현 계획
```

## 문서 작성 규칙

1. 한국어로 작성
2. ADR 번호는 순차 증가 (`find docs/decisions -name 'ADR-*.md' | sort | tail -1`)
3. 런북 번호는 순차 증가
4. 아키텍처 변경 시 `docs/architecture.md` 반드시 업데이트
5. 새 모듈 추가 시 해당 디렉토리에 모듈 문서 작성

## 참조 문서 위치

| 문서 | 경로 | 설명 |
|------|------|------|
| 아키텍처 | `docs/architecture.md` | 전체 시스템 아키텍처 |
| API 레퍼런스 | `docs/api-reference.md` | API 엔드포인트 상세 |
| 온보딩 | `docs/onboarding.md` | 개발자 온보딩 가이드 |
| ADR | `docs/decisions/ADR-*.md` | 아키텍처 결정 기록 |
| 런북 | `docs/runbooks/*.md` | 운영 절차 |
| CHANGELOG | `CHANGELOG.md` | 릴리스 변경 이력 |
