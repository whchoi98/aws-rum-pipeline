# Refactor Skill

Refactor existing code to improve quality without changing behavior.

## Principles
- Improve structure without changing behavior
- Single Responsibility Principle (SRP)
- Remove duplicate code (DRY)
- Small, incremental steps with verification

## Process

### 1. Analysis
- Identify the target code and its tests
- Map all callers and dependencies
- Confirm test coverage exists (suggest adding tests first if not)

### 2. Plan
Present the refactoring plan to the user:
- What will change
- What will NOT change (behavior preservation)
- Risk assessment (low/medium/high)

### 3. Execute
- Make changes in small, verifiable steps
- Run tests after each step if possible
  - Python: `python3 -m pytest test_handler.py -v`
  - TypeScript: `npm test` (vitest)
  - Terraform: `terraform validate`
- Keep commits atomic

### 4. Verify
- Confirm all existing tests pass
- Verify no behavior changes
- Check that the refactoring achieved its goal

## On Failure

- 테스트 실패 시 마지막 변경 롤백: `git checkout -- <파일>`
- 리팩토링 중 의존성 발견 시 Plan 단계로 돌아가 재평가
- Terraform validate 실패 시 `terraform fmt -recursive` 먼저 실행
- 타입 에러 시 `npx tsc --noEmit` 으로 전체 타입 체크

## Usage
Run with `/refactor` command
