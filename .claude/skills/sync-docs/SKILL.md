# Sync Docs Skill

Synchronize project documentation with current code state.

## Actions

### 1. Quality Assessment
Score each CLAUDE.md file (0-100) across:
- Commands/workflows (20 pts)
- Architecture clarity (20 pts)
- Non-obvious patterns (15 pts)
- Conciseness (15 pts)
- Currency (15 pts)
- Actionability (15 pts)

Output quality report with grades (A-F) before making changes.

### 2. Root CLAUDE.md Sync
- Update Overview, Tech Stack, Conventions, Key Commands
- Verify commands are copy-paste ready against actual scripts

### 3. Architecture Doc Sync
- Update docs/architecture.md to reflect current system structure
- Add new components, update data flows, reflect infrastructure changes

### 4. Module CLAUDE.md Audit
- Scan all directories under: `terraform/modules/`, `lambda/`, `sdk/`, `simulator/`, `agentcore/`, `scripts/`
- Create CLAUDE.md for modules missing one
- Update existing module CLAUDE.md files if out of date
- Score each module CLAUDE.md

### 5. ADR Audit
- Check recent commits (git log --oneline -20)
- Suggest new ADRs for undocumented architectural decisions
- Find next ADR number: `find docs/decisions -name 'ADR-*.md' | sort | tail -1`

### 6. README.md Sync
- Update project structure section to match actual directory layout

### 7. Report
Output before/after quality scores and list of all changes.

## On Failure

- 파일 읽기 실패 시 해당 파일 건너뛰고 나머지 계속 진행
- CLAUDE.md 생성 실패 시 누락 목록을 보고하고 수동 생성 안내
- git log 접근 불가 시 ADR 감사 건너뛰고 나머지 단계 진행
- 충돌 발생 시 사용자에게 확인 후 덮어쓰기 여부 결정

## Usage
Run with `/sync-docs` command
