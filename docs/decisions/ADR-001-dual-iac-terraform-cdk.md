<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

# ADR-001: Terraform + CDK 듀얼 IaC 지원

## Status
Accepted

## Context
RUM Pipeline 인프라는 Terraform (HCL)으로 관리 중.
CDK 사용 팀이 동일한 인프라를 TypeScript로 관리할 수 있도록 CDK 버전을 추가 제공할 필요가 있음.
Terraform 11개 모듈과 1:1 대응하는 CDK Construct를 작성하여 선택적 사용 가능하게 함.

## Decision
- `cdk/` 디렉터리에 AWS CDK (TypeScript) 프로젝트 추가
- Terraform 모듈 : CDK Construct = 1:1 매핑 유지
- Lambda 소스 (`lambda/`)는 Terraform과 CDK가 공유
- 보안 민감 값은 CDK context 또는 환경변수로 전달 (하드코딩 금지)
- Terraform이 primary IaC로, CDK는 대안으로 제공

## Consequences
- **장점**: CDK 사용 팀도 동일 파이프라인 배포 가능, TypeScript 타입 안전성
- **단점**: IaC 두 벌 유지 비용, 스키마 동기화 필요
- **완화**: Glue 테이블 스키마는 Terraform/CDK 간 동기화 검증 필요

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

# ADR-001: Dual IaC Support — Terraform + CDK

## Status
Accepted

## Context
The RUM Pipeline infrastructure is currently managed with Terraform (HCL).
There is a need to provide an additional CDK version so that teams using CDK can manage the same infrastructure in TypeScript.
CDK Constructs will be written in a 1:1 correspondence with the 11 Terraform modules, allowing teams to choose either approach.

## Decision
- Add an AWS CDK (TypeScript) project under the `cdk/` directory
- Maintain a 1:1 mapping between Terraform modules and CDK Constructs
- Lambda source code (`lambda/`) is shared between Terraform and CDK
- Security-sensitive values are passed via CDK context or environment variables (no hard-coding)
- Terraform remains the primary IaC; CDK is offered as an alternative

## Consequences
- **Pros**: Teams using CDK can deploy the same pipeline; TypeScript type safety
- **Cons**: Maintenance cost of two IaC codebases; schema synchronization required
- **Mitigation**: Glue table schemas must be verified for synchronization between Terraform and CDK

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
