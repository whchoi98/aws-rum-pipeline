---
description: Terraform 또는 CDK로 RUM Pipeline 배포
allowed-tools: Read, Bash(terraform:*), Bash(npx:*), Bash(git:*), Bash(cd:*), Glob
---

# Deploy

RUM Pipeline 인프라를 배포합니다.

## Step 1: 사전 점검

1. 작업 트리 정리 확인: `git status`
2. 현재 브랜치 확인 (main이 아닌 경우 경고)
3. 배포 런북 확인: `docs/runbooks/01-initial-deployment.md`

## Step 2: 배포 방식 선택

$ARGUMENTS에 따라 배포 방식 결정:
- `terraform` (기본값): Terraform으로 배포
- `cdk`: AWS CDK로 배포
- 참고: ADR-001에 따라 Terraform과 CDK는 동일 인프라를 관리

### Terraform 배포

```bash
cd terraform && terraform fmt -recursive
cd terraform && terraform plan -out=tfplan
```

> **STOP** — plan 출력을 사용자에게 보여주세요.
> 사용자가 "apply", "배포", "진행" 등으로 명시적으로 확인하기 전까지
> 절대 `terraform apply`를 실행하지 마세요.

사용자 확인 후:
```bash
cd terraform && terraform apply tfplan
```

### CDK 배포

```bash
cd cdk && npm install
cd cdk && npx cdk synth
```

> **STOP** — synth 출력을 사용자에게 보여주세요.
> 사용자가 명시적으로 확인하기 전까지 `cdk deploy`를 실행하지 마세요.

사용자 확인 후:
```bash
cd cdk && npx cdk deploy
```

## Step 3: 검증

배포 후:
- API Gateway 엔드포인트 확인
- 통합 테스트 스크립트 실행 제안: `bash scripts/test-ingestion.sh`
- CloudWatch 대시보드 확인 제안

## Step 4: 요약

- 배포된 항목과 위치
- 사용된 배포 방식
- 검증 결과
- 런북이 없으면 생성 제안

## On Failure

| 실패 지점 | 조치 |
|-----------|------|
| `terraform plan` 실패 | `terraform validate` 실행 → 에러 수정 → 재시도 |
| `terraform apply` 실패 | `terraform state list`로 부분 적용 확인 → 런북 03 참조 |
| `cdk synth` 실패 | TypeScript 컴파일 에러 확인 → `npx tsc --noEmit` 실행 |
| `cdk deploy` 실패 | `cdk diff`로 드리프트 확인 → CloudFormation 콘솔에서 스택 상태 확인 |
| 배포 후 검증 실패 | 즉시 롤백하지 말고 CloudWatch 로그 확인 → 런북 07 참조 |
