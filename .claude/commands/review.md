---
description: 코드 변경사항 리뷰 (confidence 기반 필터링)
allowed-tools: Read, Glob, Grep, Bash(git diff:*), Bash(git log:*)
---

# Code Review

현재 코드 변경사항을 confidence 기반 스코어링으로 리뷰합니다.

## Step 1: 변경 범위 확인

- $ARGUMENTS에 파일이 지정된 경우 해당 파일 리뷰
- 그 외: unstaged 변경 확인 `git diff`
- unstaged 변경 없으면 staged 변경 확인 `git diff --cached`

## Step 2: 리뷰

변경된 각 파일에 대해 코드 리뷰 스킬 기준 적용:
- CLAUDE.md 프로젝트 가이드라인 준수 (한국어 주석, terraform fmt, Black 포맷터 등)
- 버그 감지 (로직 오류, 보안, 성능)
- 코드 품질 (중복, 복잡도, 테스트 커버리지)
- Terraform: 모듈 경계, 변수 네이밍, 리소스 태깅
- Python Lambda: type hints, 에러 핸들링, pytest 테스트
- TypeScript SDK: strict 타입, ESM 호환성

## Step 3: 스코어링 및 필터

각 이슈를 0-100으로 평가. confidence >= 75인 이슈만 보고.

## Step 4: 출력

파일 경로, 라인 번호, 수정 제안과 함께 구조화된 형식으로 결과 제시.
고신뢰도 이슈가 없으면 코드가 기준을 충족함을 간략히 확인.

## On Failure

- `git diff` 출력이 없으면 staged 변경 확인 (`git diff --cached`)
- staged 변경도 없으면 "리뷰할 변경사항이 없습니다" 보고 후 종료
- 파일 읽기 실패 시 해당 파일 건너뛰고 나머지 파일 계속 리뷰
- 리뷰 기준 참조: `.claude/skills/code-review/SKILL.md`
