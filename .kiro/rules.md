# 프로젝트 규칙

## 금지 사항

- 시크릿(API Key, 토큰, 비밀번호)을 코드에 하드코딩하지 않는다.
- `terraform destroy`, `terraform apply -auto-approve`를 자동 실행하지 않는다.
- `git push --force`, `git reset --hard`를 실행하지 않는다.
- `rm -rf /`, `rm -rf ~`, `chmod 777`을 실행하지 않는다.
- `tfplan` 파일을 Git에 커밋하지 않는다.
- `.env` 파일을 Git에 커밋하지 않는다 (`.env.example`만 커밋).

## 배포 규칙

- `terraform apply` 전에 반드시 `terraform plan` 결과를 사용자에게 보여주고 확인을 받는다.
- `cdk deploy` 전에 반드시 `cdk synth` 결과를 사용자에게 보여주고 확인을 받는다.
- 프로덕션 배포는 main 브랜치에서만 수행한다.

## 코드 품질

- Python: Black 포맷터, type hints 사용.
- TypeScript: strict 모드, ESM.
- Terraform: `terraform fmt -recursive` 필수.
- 한국어 주석 우선.
- Conventional Commits 형식 (feat:, fix:, docs:, chore:, refactor:, test:).

## 문서 동기화

- 새 모듈/함수 추가 시 해당 디렉토리에 문서를 작성한다.
- 아키텍처 변경 시 `docs/architecture.md`를 업데이트한다.
- 아키텍처 결정 시 ADR을 작성한다.
- 운영 절차 정의 시 런북을 작성한다.
