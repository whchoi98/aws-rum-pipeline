#!/bin/bash
# PreToolUse hook: 파일 쓰기/커밋 시 시크릿 패턴 감지
# 시크릿 감지 시 exit 1로 도구 실행 차단

FILE="$1"
if [ -z "$FILE" ]; then exit 0; fi

# 검사 대상 확장자만
case "$FILE" in
  *.tf|*.ts|*.py|*.js|*.json|*.md|*.sh|*.yaml|*.yml|*.env|*.cfg) ;;
  *) exit 0 ;;
esac

# 파일 존재 확인
[ -f "$FILE" ] || exit 0

FOUND=0

# 시크릿 패턴
PATTERNS=(
  'AKIA[0-9A-Z]{16}'                          # AWS Access Key ID
  'aws_secret_access_key\s*[:=]\s*["\x27][A-Za-z0-9/+=]{40}'  # AWS Secret Access Key
  'glsa_[A-Za-z0-9_]+'                        # Grafana Service Account Token
  'ghp_[A-Za-z0-9]{36}'                       # GitHub Personal Access Token
  'sk-[A-Za-z0-9]{48}'                        # OpenAI/Anthropic API Key
  'password\s*[:=]\s*["\x27][^"\x27]+'        # Hardcoded passwords
  '-----BEGIN.*PRIVATE KEY-----'              # Private keys (RSA, EC, etc.)
  'eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.'  # JWT tokens
  'https://hooks\.slack\.com/services/[A-Za-z0-9/]+'  # Slack webhook URLs
  'xox[bpas]-[A-Za-z0-9-]+'                  # Slack tokens
)

for pattern in "${PATTERNS[@]}"; do
  if grep -qPn -- "$pattern" "$FILE" 2>/dev/null; then
    echo "BLOCKED: Potential secret detected in $FILE (pattern: $pattern)"
    FOUND=1
  fi
done

exit $FOUND
