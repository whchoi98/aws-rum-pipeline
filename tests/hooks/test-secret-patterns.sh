#!/bin/bash
# 시크릿 패턴 참양성/거짓양성 검증.

SCAN_SCRIPT=".claude/hooks/secret-scan.sh"
TP_FILE="tests/fixtures/secret-samples.txt"
FP_FILE="tests/fixtures/false-positives.txt"

echo "# Secret pattern: true positives"
if [ -f "$TP_FILE" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        TOTAL=$((TOTAL + 1))
        # 임시 파일에 패턴 기록 후 스캔
        TMPFILE=$(mktemp /tmp/secret-test-XXXXXX.tf)
        echo "$line" > "$TMPFILE"
        RESULT=$(bash "$SCAN_SCRIPT" "$TMPFILE" 2>/dev/null)
        rm -f "$TMPFILE"
        if echo "$RESULT" | grep -qi "BLOCKED\|WARNING"; then
            echo -e "${GREEN}ok ${TOTAL}${NC} - detects: ${line:0:40}..."
            PASS=$((PASS + 1))
        else
            echo -e "${RED}not ok ${TOTAL}${NC} - missed true positive: ${line:0:40}..."
            FAIL=$((FAIL + 1))
        fi
    done < "$TP_FILE"
fi

echo "# Secret pattern: false positives"
if [ -f "$FP_FILE" ]; then
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        [[ "$line" == \#* ]] && continue
        TOTAL=$((TOTAL + 1))
        TMPFILE=$(mktemp /tmp/secret-test-XXXXXX.tf)
        echo "$line" > "$TMPFILE"
        RESULT=$(bash "$SCAN_SCRIPT" "$TMPFILE" 2>/dev/null)
        rm -f "$TMPFILE"
        if echo "$RESULT" | grep -qi "BLOCKED\|WARNING"; then
            echo -e "${RED}not ok ${TOTAL}${NC} - false positive: ${line:0:40}..."
            FAIL=$((FAIL + 1))
        else
            echo -e "${GREEN}ok ${TOTAL}${NC} - correctly ignores: ${line:0:40}..."
            PASS=$((PASS + 1))
        fi
    done < "$FP_FILE"
fi
