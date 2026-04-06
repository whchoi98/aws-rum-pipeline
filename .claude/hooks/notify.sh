#!/bin/bash
# Claude Code 이벤트 알림 웹훅 훅.
# Notification 이벤트 시 자동 실행.
# CLAUDE_NOTIFY_WEBHOOK 환경변수를 설정하면 활성화.

WEBHOOK_URL="${CLAUDE_NOTIFY_WEBHOOK:-}"
[ -z "$WEBHOOK_URL" ] && exit 0

EVENT="${1:-unknown}"
MESSAGE="${2:-Claude Code event occurred}"

# 페이로드 빌드
PAYLOAD=$(cat <<EOF
{
  "text": "[$EVENT] $MESSAGE",
  "project": "aws-rum-pipeline",
  "branch": "$(git branch --show-current 2>/dev/null || echo 'unknown')",
  "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
EOF
)

# 비동기 알림 전송
curl -s -X POST "$WEBHOOK_URL" \
    -H "Content-Type: application/json" \
    -d "$PAYLOAD" > /dev/null 2>&1 &
