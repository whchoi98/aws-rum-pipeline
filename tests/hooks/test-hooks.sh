#!/bin/bash
# 훅 존재, 실행 권한, 설정 등록, 통합 경로 검증.

echo "# Hook existence"
assert_file_exists ".claude/hooks/check-doc-sync.sh" "check-doc-sync.sh exists"
assert_file_exists ".claude/hooks/secret-scan.sh" "secret-scan.sh exists"
assert_file_exists ".claude/hooks/session-context.sh" "session-context.sh exists"
assert_file_exists ".claude/hooks/notify.sh" "notify.sh exists"

echo "# Hook permissions"
assert_executable ".claude/hooks/check-doc-sync.sh" "check-doc-sync.sh is executable"
assert_executable ".claude/hooks/secret-scan.sh" "secret-scan.sh is executable"
assert_executable ".claude/hooks/session-context.sh" "session-context.sh is executable"
assert_executable ".claude/hooks/notify.sh" "notify.sh is executable"

echo "# Hook registration in settings.json"
assert_contains ".claude/settings.json" "SessionStart" "SessionStart hook registered"
assert_contains ".claude/settings.json" "PreToolUse" "PreToolUse hook registered"
assert_contains ".claude/settings.json" "PostToolUse" "PostToolUse hook registered"
assert_contains ".claude/settings.json" "Notification" "Notification hook registered"

echo "# Hook script syntax"
for hook in .claude/hooks/*.sh; do
    TOTAL=$((TOTAL + 1))
    if bash -n "$hook" 2>/dev/null; then
        echo -e "${GREEN}ok ${TOTAL}${NC} - $(basename $hook) has valid syntax"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}not ok ${TOTAL}${NC} - $(basename $hook) has syntax errors"
        FAIL=$((FAIL + 1))
    fi
done

echo "# Hook behavior: session-context.sh produces output"
TOTAL=$((TOTAL + 1))
OUTPUT=$(bash .claude/hooks/session-context.sh 2>/dev/null)
if [ -n "$OUTPUT" ]; then
    echo -e "${GREEN}ok ${TOTAL}${NC} - session-context.sh produces output"
    PASS=$((PASS + 1))
else
    echo -e "${RED}not ok ${TOTAL}${NC} - session-context.sh produces no output"
    FAIL=$((FAIL + 1))
fi

echo "# Integration: secret-scan.sh blocks on secret file"
TOTAL=$((TOTAL + 1))
TMPFILE=$(mktemp /tmp/secret-integration-XXXXXX.tf)
echo 'aws_access_key_id = "AKIAIOSFODNN7EXAMPLE"' > "$TMPFILE"
bash .claude/hooks/secret-scan.sh "$TMPFILE" >/dev/null 2>&1
SCAN_EXIT=$?
rm -f "$TMPFILE"
if [ "$SCAN_EXIT" -ne 0 ]; then
    echo -e "${GREEN}ok ${TOTAL}${NC} - secret-scan.sh exits non-zero on secret (exit=$SCAN_EXIT)"
    PASS=$((PASS + 1))
else
    echo -e "${RED}not ok ${TOTAL}${NC} - secret-scan.sh should exit non-zero on secret"
    FAIL=$((FAIL + 1))
fi

echo "# Integration: secret-scan.sh passes clean file"
TOTAL=$((TOTAL + 1))
TMPFILE=$(mktemp /tmp/secret-clean-XXXXXX.tf)
echo 'resource "aws_s3_bucket" "example" {}' > "$TMPFILE"
bash .claude/hooks/secret-scan.sh "$TMPFILE" >/dev/null 2>&1
SCAN_EXIT=$?
rm -f "$TMPFILE"
if [ "$SCAN_EXIT" -eq 0 ]; then
    echo -e "${GREEN}ok ${TOTAL}${NC} - secret-scan.sh exits 0 on clean file"
    PASS=$((PASS + 1))
else
    echo -e "${RED}not ok ${TOTAL}${NC} - secret-scan.sh should exit 0 on clean file"
    FAIL=$((FAIL + 1))
fi

echo "# Integration: secret-scan.sh exits 0 with no args"
TOTAL=$((TOTAL + 1))
bash .claude/hooks/secret-scan.sh >/dev/null 2>&1
SCAN_EXIT=$?
if [ "$SCAN_EXIT" -eq 0 ]; then
    echo -e "${GREEN}ok ${TOTAL}${NC} - secret-scan.sh exits 0 with no args"
    PASS=$((PASS + 1))
else
    echo -e "${RED}not ok ${TOTAL}${NC} - secret-scan.sh should exit 0 with no args"
    FAIL=$((FAIL + 1))
fi

echo "# Hook wiring: Write|Edit matcher registered for secret scan"
assert_contains ".claude/settings.json" "Write|Edit" "Write|Edit secret-scan matcher registered"

echo "# Hook wiring: secret-scan not suppressed by || true"
assert_not_contains ".claude/settings.json" "secret-scan.sh 2>/dev/null || true" "secret-scan hook not suppressed by || true"
