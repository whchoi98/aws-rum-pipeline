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
# 사용자 확인 후:
cd terraform && terraform apply tfplan
```

### CDK 배포

```bash
cd cdk && npm install
cd cdk && npx cdk synth
# 사용자 확인 후:
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
