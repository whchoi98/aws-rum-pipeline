#!/bin/bash
# Git 훅 설치 스크립트.
# 사용법: bash scripts/install-hooks.sh

set -e

HOOKS_DIR=".git/hooks"

if [ ! -d "$HOOKS_DIR" ]; then
    echo "ERROR: .git/hooks 디렉토리를 찾을 수 없습니다. Git 저장소인지 확인하세요."
    exit 1
fi

# commit-msg 훅 설치 (Co-Authored-By 라인 자동 제거)
cat > "$HOOKS_DIR/commit-msg" << 'HOOK'
#!/bin/bash
# 커밋 메시지에서 Co-Authored-By 라인을 제거합니다.
# Claude 등 AI 어시스턴트가 커밋 기여자로 표시되는 것을 방지합니다.
sed -i '/^[Cc]o-[Aa]uthored-[Bb]y:.*/d' "$1"
sed -i -e :a -e '/^\n*$/{$d;N;ba' -e '}' "$1"
HOOK
chmod +x "$HOOKS_DIR/commit-msg"
echo "[OK] commit-msg 훅 설치 완료 (AI co-author 제거)"

# Claude 훅 스크립트 실행 권한 부여
if [ -d ".claude/hooks" ]; then
    chmod +x .claude/hooks/*.sh 2>/dev/null
    echo "[OK] Claude 훅 스크립트 실행 권한 설정 완료"
fi

echo "=== Git 훅 설치 완료 ==="
