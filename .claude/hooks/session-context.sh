#!/bin/bash
# RUM Pipeline 프로젝트 컨텍스트 로딩 훅.
# SessionStart 이벤트 시 자동 실행.

echo "=== Project Context ==="
echo "Project: aws-rum-pipeline (AWS Serverless RUM)"
echo "Stack: Terraform + CDK (TS) | Lambda (Python 3.12) | SDK (TS) | iOS (Swift) | Android (Kotlin)"

# 최근 커밋
LAST_COMMIT=$(git log -1 --format="%h %s (%cr)" 2>/dev/null)
[ -n "$LAST_COMMIT" ] && echo "Last commit: $LAST_COMMIT"

# 브랜치 정보
BRANCH=$(git branch --show-current 2>/dev/null)
[ -n "$BRANCH" ] && echo "Branch: $BRANCH"

# 미커밋 변경 사항
CHANGES=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
[ "$CHANGES" -gt 0 ] && echo "Uncommitted changes: $CHANGES file(s)"

# 문서 현황
CLAUDE_COUNT=$(find . -name "CLAUDE.md" -not -path "./.git/*" -not -path "*/node_modules/*" 2>/dev/null | wc -l | tr -d ' ')
ADR_COUNT=$(find docs/decisions -name 'ADR-*.md' -not -name '.template.md' 2>/dev/null | wc -l | tr -d ' ')
RUNBOOK_COUNT=$(find docs/runbooks -name '*.md' -not -name '.template.md' 2>/dev/null | wc -l | tr -d ' ')
echo "Docs: ${CLAUDE_COUNT} CLAUDE.md | ${ADR_COUNT} ADRs | ${RUNBOOK_COUNT} runbooks"

echo "======================"
