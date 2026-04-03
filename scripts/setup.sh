#!/usr/bin/env bash
# =============================================================================
# RUM Pipeline — 전체 설치 스크립트
# =============================================================================
# 사용법: ./scripts/setup.sh [phase]
#   ./scripts/setup.sh all          # 전체 설치 (기본값)
#   ./scripts/setup.sh infra        # Phase 1: Terraform 인프라만
#   ./scripts/setup.sh sdk          # Phase 2: SDK 빌드
#   ./scripts/setup.sh simulator    # Phase 3: 시뮬레이터 로컬 실행
#   ./scripts/setup.sh grafana      # Phase 4: Grafana 대시보드 프로비저닝
#   ./scripts/setup.sh eks          # Phase 5: EKS CronJob 배포
#   ./scripts/setup.sh test         # 전체 테스트 실행
# =============================================================================

set -euo pipefail
cd "$(dirname "$0")/.."

PHASE="${1:-all}"
REGION="ap-northeast-2"

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[RUM]${NC} $*"; }
ok()   { echo -e "${GREEN}[OK]${NC} $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

# =============================================================================
# 사전 조건 확인
# =============================================================================
check_prerequisites() {
    log "사전 조건 확인 중..."
    command -v terraform >/dev/null || err "terraform이 설치되지 않았습니다"
    command -v aws >/dev/null || err "aws CLI가 설치되지 않았습니다"
    command -v node >/dev/null || err "node.js가 설치되지 않았습니다"
    command -v python3 >/dev/null || err "python3이 설치되지 않았습니다"

    # AWS 자격증명 확인
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>/dev/null) || err "AWS 자격증명이 설정되지 않았습니다"
    ok "AWS 계정: ${ACCOUNT_ID} (리전: ${REGION})"
}

# =============================================================================
# Phase 1: Terraform 인프라 배포
# =============================================================================
deploy_infra() {
    log "=========================================="
    log "Phase 1: Terraform 인프라 배포"
    log "=========================================="

    cd terraform

    log "terraform init..."
    terraform init -input=false

    log "terraform plan..."
    terraform plan -out=tfplan

    log "terraform apply..."
    terraform apply tfplan
    rm -f tfplan

    # 출력값 저장
    API_ENDPOINT=$(terraform output -raw api_endpoint)
    S3_BUCKET=$(terraform output -raw s3_bucket_name)
    API_KEY_SSM=$(terraform output -raw api_key_ssm_name)

    ok "API Endpoint: ${API_ENDPOINT}"
    ok "S3 Bucket: ${S3_BUCKET}"
    ok "API Key SSM: ${API_KEY_SSM}"

    cd ..
}

# =============================================================================
# Phase 2: SDK 빌드
# =============================================================================
build_sdk() {
    log "=========================================="
    log "Phase 2: SDK 빌드"
    log "=========================================="

    cd sdk
    log "npm install..."
    npm install --silent

    log "테스트 실행..."
    npx vitest run

    log "SDK 빌드..."
    npm run build

    IIFE_SIZE=$(wc -c < dist/rum-sdk.min.js)
    ok "SDK 빌드 완료 — rum-sdk.min.js: ${IIFE_SIZE} bytes"

    cd ..
}

# =============================================================================
# Phase 3: 시뮬레이터 로컬 테스트
# =============================================================================
run_simulator() {
    log "=========================================="
    log "Phase 3: 시뮬레이터 테스트"
    log "=========================================="

    cd simulator
    log "npm install..."
    npm install --silent

    log "단위 테스트..."
    npx vitest run

    log "API 키 조회..."
    API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys --with-decryption --query Parameter.Value --output text --region ${REGION})
    API_ENDPOINT=$(cd ../terraform && terraform output -raw api_endpoint)

    log "시뮬레이터 실행 (10 이벤트 x 2 세션)..."
    RUM_API_ENDPOINT="${API_ENDPOINT}" \
    RUM_API_KEY="${API_KEY}" \
    EVENTS_PER_BATCH=10 \
    CONCURRENT_SESSIONS=2 \
    npx tsx src/index.ts

    ok "시뮬레이터 테스트 완료"
    cd ..
}

# =============================================================================
# Phase 4: Grafana 대시보드 프로비저닝
# =============================================================================
provision_grafana() {
    log "=========================================="
    log "Phase 4: Grafana 대시보드 프로비저닝"
    log "=========================================="

    WORKSPACE_ID=$(cd terraform && terraform output -raw grafana_workspace_id)
    GRAFANA_URL=$(cd terraform && terraform output -raw grafana_workspace_endpoint)

    log "Grafana 서비스 계정 토큰 생성..."
    # 기존 서비스 계정 확인
    SA_ID=$(aws grafana list-workspace-service-accounts --workspace-id "${WORKSPACE_ID}" --region ${REGION} --query 'serviceAccounts[0].id' --output text 2>/dev/null || echo "None")

    if [ "${SA_ID}" = "None" ] || [ -z "${SA_ID}" ]; then
        SA_ID=$(aws grafana create-workspace-service-account --workspace-id "${WORKSPACE_ID}" --name "setup-sa" --grafana-role ADMIN --region ${REGION} --query 'id' --output text)
    fi

    TOKEN=$(aws grafana create-workspace-service-account-token --workspace-id "${WORKSPACE_ID}" --service-account-id "${SA_ID}" --name "setup-$(date +%s)" --seconds-to-live 3600 --region ${REGION} --query 'serviceAccountToken.key' --output text)

    log "대시보드 배포..."
    TOKEN="${TOKEN}" python3 scripts/deploy-unified-dashboard.py

    ok "Grafana URL: ${GRAFANA_URL}"
    ok "대시보드 배포 완료"
}

# =============================================================================
# Phase 5: EKS CronJob 배포
# =============================================================================
deploy_eks() {
    log "=========================================="
    log "Phase 5: EKS CronJob 배포"
    log "=========================================="

    EKS_CLUSTER="${EKS_CLUSTER:-eksworkshop}"
    log "EKS 클러스터: ${EKS_CLUSTER}"

    aws eks update-kubeconfig --name "${EKS_CLUSTER}" --region ${REGION}

    # Namespace 생성
    kubectl create namespace rum 2>/dev/null || true

    # API Key Secret 생성
    API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys --with-decryption --query Parameter.Value --output text --region ${REGION})
    kubectl create secret generic rum-api-key --from-literal=api-key="${API_KEY}" -n rum 2>/dev/null || \
        kubectl delete secret rum-api-key -n rum && kubectl create secret generic rum-api-key --from-literal=api-key="${API_KEY}" -n rum

    # CronJob 배포
    kubectl apply -f simulator/k8s/cronjob.yaml

    ok "CronJob 배포 완료"
    kubectl get cronjob -n rum
}

# =============================================================================
# 전체 테스트
# =============================================================================
run_tests() {
    log "=========================================="
    log "전체 테스트 실행"
    log "=========================================="

    log "[1/4] Lambda 단위 테스트 (authorizer)..."
    (cd lambda/authorizer && python3 -m pytest test_handler.py -v)

    log "[2/4] Lambda 단위 테스트 (ingest)..."
    (cd lambda/ingest && python3 -m pytest test_handler.py -v)

    log "[3/4] Lambda 단위 테스트 (transform)..."
    (cd lambda/transform && python3 -m pytest test_handler.py -v)

    log "[4/4] SDK 단위 테스트..."
    (cd sdk && npx vitest run)

    log "[5/5] 시뮬레이터 단위 테스트..."
    (cd simulator && npx vitest run)

    API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys --with-decryption --query Parameter.Value --output text --region ${REGION})
    API_ENDPOINT=$(cd terraform && terraform output -raw api_endpoint)

    log "[E2E] 통합 테스트..."
    bash scripts/test-ingestion.sh "${API_ENDPOINT}" "${API_KEY}"

    ok "전체 테스트 통과"
}

# =============================================================================
# 실행
# =============================================================================
check_prerequisites

case "${PHASE}" in
    all)
        deploy_infra
        build_sdk
        run_simulator
        provision_grafana
        run_tests
        log "=========================================="
        ok "전체 설치 완료!"
        log "=========================================="
        log ""
        log "주요 URL:"
        API_ENDPOINT=$(cd terraform && terraform output -raw api_endpoint)
        GRAFANA_URL=$(cd terraform && terraform output -raw grafana_workspace_endpoint)
        log "  API:      ${API_ENDPOINT}"
        log "  Grafana:  ${GRAFANA_URL}"
        log "  CW 대시보드: https://${REGION}.console.aws.amazon.com/cloudwatch/home?region=${REGION}#dashboards/dashboard/rum-pipeline-dashboard"
        log "  SSO 포털:  https://d-9b6773f833.awsapps.com/start"
        ;;
    infra)     deploy_infra ;;
    sdk)       build_sdk ;;
    simulator) run_simulator ;;
    grafana)   provision_grafana ;;
    eks)       deploy_eks ;;
    test)      run_tests ;;
    *)         err "알 수 없는 phase: ${PHASE}. 사용법: $0 [all|infra|sdk|simulator|grafana|eks|test]" ;;
esac
