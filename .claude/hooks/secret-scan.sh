#!/bin/bash
# PreToolUse hook: 파일 쓰기 시 시크릿 패턴 감지
# Scans for secrets before file writes

FILE="$1"
if [ -z "$FILE" ]; then exit 0; fi

# 검사 대상 확장자만
case "$FILE" in
  *.tf|*.ts|*.py|*.js|*.json|*.md|*.sh|*.yaml|*.yml) ;;
  *) exit 0 ;;
esac

# 시크릿 패턴
PATTERNS=(
  'AKIA[0-9A-Z]{16}'           # AWS Access Key
  '[0-9]{12}'                   # AWS Account ID (12 digits standalone)
  'glsa_[A-Za-z0-9_]+'         # Grafana Service Account Token
  'ghp_[A-Za-z0-9]{36}'        # GitHub Personal Access Token
  'sk-[A-Za-z0-9]{48}'         # OpenAI/Anthropic API Key
  'password\s*[:=]\s*["\x27][^"\x27]+'  # Hardcoded passwords
)

for pattern in "${PATTERNS[@]}"; do
  if grep -qPn "$pattern" "$FILE" 2>/dev/null; then
    echo "WARNING: Potential secret detected in $FILE (pattern: $pattern)"
  fi
done

exit 0
