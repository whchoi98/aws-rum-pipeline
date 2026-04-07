#!/bin/bash
# TAP 스타일 테스트 러너 — Claude Code 하네스 검증.
# 사용법: bash tests/run-all.sh

set -uo pipefail
cd "$(dirname "$0")/.."

PASS=0
FAIL=0
TOTAL=0

# 색상 코드
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# TAP 어설션 함수
assert_file_exists() {
    TOTAL=$((TOTAL + 1))
    if [ -f "$1" ]; then
        echo -e "${GREEN}ok ${TOTAL}${NC} - $2"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}not ok ${TOTAL}${NC} - $2 (file not found: $1)"
        FAIL=$((FAIL + 1))
    fi
}

assert_dir_exists() {
    TOTAL=$((TOTAL + 1))
    if [ -d "$1" ]; then
        echo -e "${GREEN}ok ${TOTAL}${NC} - $2"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}not ok ${TOTAL}${NC} - $2 (dir not found: $1)"
        FAIL=$((FAIL + 1))
    fi
}

assert_executable() {
    TOTAL=$((TOTAL + 1))
    if [ -x "$1" ]; then
        echo -e "${GREEN}ok ${TOTAL}${NC} - $2"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}not ok ${TOTAL}${NC} - $2 (not executable: $1)"
        FAIL=$((FAIL + 1))
    fi
}

assert_contains() {
    TOTAL=$((TOTAL + 1))
    if grep -q "$2" "$1" 2>/dev/null; then
        echo -e "${GREEN}ok ${TOTAL}${NC} - $3"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}not ok ${TOTAL}${NC} - $3 (pattern not found in $1)"
        FAIL=$((FAIL + 1))
    fi
}

assert_not_contains() {
    TOTAL=$((TOTAL + 1))
    if ! grep -q "$2" "$1" 2>/dev/null; then
        echo -e "${GREEN}ok ${TOTAL}${NC} - $3"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}not ok ${TOTAL}${NC} - $3 (unwanted pattern found in $1)"
        FAIL=$((FAIL + 1))
    fi
}

assert_json_valid() {
    TOTAL=$((TOTAL + 1))
    if python3 -c "import json; json.load(open('$1'))" 2>/dev/null; then
        echo -e "${GREEN}ok ${TOTAL}${NC} - $2"
        PASS=$((PASS + 1))
    else
        echo -e "${RED}not ok ${TOTAL}${NC} - $2 (invalid JSON: $1)"
        FAIL=$((FAIL + 1))
    fi
}

echo "TAP version 14"
echo "# RUM Pipeline Harness Validation"
echo ""

# 개별 테스트 스위트 실행
echo "# === Hook Tests ==="
for test_file in tests/hooks/test-*.sh; do
    [ -f "$test_file" ] && source "$test_file"
done

echo ""
echo "# === Structure Tests ==="
for test_file in tests/structure/test-*.sh; do
    [ -f "$test_file" ] && source "$test_file"
done

# 결과 요약
echo ""
echo "1..${TOTAL}"
echo "---"
echo -e "# ${GREEN}passed: ${PASS}${NC}"
[ "$FAIL" -gt 0 ] && echo -e "# ${RED}failed: ${FAIL}${NC}" || echo "# failed: 0"
echo "# total: ${TOTAL}"
echo "---"

[ "$FAIL" -eq 0 ] && exit 0 || exit 1
