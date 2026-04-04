# 프로젝트 문서 가이드

## 문서 구조

```
docs/
├── architecture.md          # 전체 시스템 아키텍처
├── decisions/               # Architecture Decision Records (ADR)
│   ├── .template.md         # ADR 템플릿
│   ├── ADR-001-*.md         # Terraform + CDK 듀얼 IaC
│   └── ADR-002-*.md         # Cognito SSO + Lambda@Edge
├── runbooks/                # 운영 런북 (01~09)
│   └── .template.md         # 런북 템플릿
└── superpowers/             # 설계 스펙 및 구현 계획
    ├── specs/               # 설계 문서 (4개)
    └── plans/               # 구현 계획 (4개)
```

## 문서 작성 규칙

1. 한국어로 작성
2. ADR 번호는 순차 증가 (`find docs/decisions -name 'ADR-*.md' | sort | tail -1`)
3. 런북 번호는 순차 증가
4. 아키텍처 변경 시 `docs/architecture.md` 반드시 업데이트
5. 새 모듈 추가 시 해당 디렉토리에 모듈 문서 작성
