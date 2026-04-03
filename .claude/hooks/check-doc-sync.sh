#!/bin/bash
# RUM Pipeline 프로젝트 문서 동기화 감지 훅.
# PostToolUse (Write|Edit) 이벤트 후 자동 실행.

FILE_PATH="${1:-}"
[ -z "$FILE_PATH" ] && exit 0

# terraform/, lambda/, sdk/, simulator/, agentcore/ 서브디렉토리에 CLAUDE.md 누락 감지
for SRC_DIR in terraform lambda sdk simulator agentcore scripts; do
    if [[ "$FILE_PATH" == ${SRC_DIR}/* ]]; then
        DIR=$(dirname "$FILE_PATH")
        if [ ! -f "$DIR/CLAUDE.md" ] && [ "$DIR" != "$SRC_DIR" ]; then
            echo "[doc-sync] $DIR/CLAUDE.md is missing. Create module documentation."
        fi
    fi
done

# 소스 또는 아키텍처 파일 변경 시 ADR 부재 경고
if [[ "$FILE_PATH" == terraform/* ]] || \
   [[ "$FILE_PATH" == lambda/* ]] || \
   [[ "$FILE_PATH" == sdk/* ]] || \
   [[ "$FILE_PATH" == simulator/* ]] || \
   [[ "$FILE_PATH" == agentcore/* ]] || \
   [[ "$FILE_PATH" == docs/architecture.md ]]; then
    ADR_COUNT=$(find docs/decisions -name 'ADR-*.md' 2>/dev/null | wc -l)
    if [ "$ADR_COUNT" -eq 0 ]; then
        echo "[doc-sync] No ADRs found. Record architectural decisions in docs/decisions/."
    fi
fi

# Terraform 모듈 추가 감지
if [[ "$FILE_PATH" == terraform/modules/*/main.tf ]]; then
    MODULE_DIR=$(dirname "$FILE_PATH")
    if [ ! -f "$MODULE_DIR/CLAUDE.md" ]; then
        echo "[doc-sync] $MODULE_DIR/CLAUDE.md is missing. Document this Terraform module."
    fi
fi
