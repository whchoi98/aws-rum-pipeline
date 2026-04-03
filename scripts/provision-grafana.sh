#!/usr/bin/env bash
# scripts/provision-grafana.sh
# Provisions Grafana Athena data source and imports 3 RUM dashboards via the Grafana API.
#
# Prerequisites:
#   - GRAFANA_URL: Grafana workspace URL (e.g. https://<id>.grafana-workspace.ap-northeast-2.amazonaws.com)
#   - GRAFANA_API_KEY: Service account token with Admin role
#   - AWS_REGION: AWS region (default: ap-northeast-2)
#   - ATHENA_WORKGROUP: Athena workgroup name (default: rum-pipeline-athena)
#   - ACCOUNT_ID: AWS account ID (required)
#   - S3_BUCKET: S3 bucket name for Athena results (default: rum-pipeline-data-lake-<account-id>)
#   - GLUE_DATABASE: Glue database name (default: rum_pipeline_db)
#
# Usage:
#   export GRAFANA_URL=https://<workspace-id>.grafana-workspace.ap-northeast-2.amazonaws.com
#   export GRAFANA_API_KEY=<service-account-token>
#   ./scripts/provision-grafana.sh

set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:?Set GRAFANA_URL to the Grafana workspace URL}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:?Set GRAFANA_API_KEY to a Grafana service account token}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ATHENA_WORKGROUP="${ATHENA_WORKGROUP:-rum-pipeline-athena}"
ACCOUNT_ID="${ACCOUNT_ID:?Set ACCOUNT_ID to your AWS account ID}"
S3_BUCKET="${S3_BUCKET:-rum-pipeline-data-lake-${ACCOUNT_ID}}"
GLUE_DATABASE="${GLUE_DATABASE:-rum_pipeline_db}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARDS_DIR="${SCRIPT_DIR}/../terraform/modules/grafana/dashboards"

GRAFANA_API="${GRAFANA_URL}/api"
AUTH_HEADER="Authorization: Bearer ${GRAFANA_API_KEY}"
CONTENT_HEADER="Content-Type: application/json"

echo "=== Grafana RUM Dashboard Provisioning ==="
echo "Workspace: ${GRAFANA_URL}"
echo "Region:    ${AWS_REGION}"
echo "Workgroup: ${ATHENA_WORKGROUP}"
echo "Bucket:    s3://${S3_BUCKET}/athena-results/"
echo ""

# ── Step 1: Verify Grafana connectivity ──────────────────────────────────────
echo "--- Step 1: Verify Grafana connectivity ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "${AUTH_HEADER}" \
  "${GRAFANA_API}/health")
if [ "${HTTP_CODE}" != "200" ]; then
  echo "FAIL: Cannot reach Grafana API (HTTP ${HTTP_CODE}). Check GRAFANA_URL and GRAFANA_API_KEY."
  exit 1
fi
echo "PASS: Grafana API reachable"
echo ""

# ── Step 2: Create Athena data source ────────────────────────────────────────
echo "--- Step 2: Create Athena data source ---"
DATASOURCE_PAYLOAD=$(cat <<EOF
{
  "name": "Amazon Athena — RUM Pipeline",
  "type": "grafana-athena-datasource",
  "access": "proxy",
  "isDefault": true,
  "jsonData": {
    "authType": "default",
    "defaultRegion": "${AWS_REGION}",
    "catalog": "AwsDataCatalog",
    "database": "${GLUE_DATABASE}",
    "workgroup": "${ATHENA_WORKGROUP}",
    "outputLocation": "s3://${S3_BUCKET}/athena-results/"
  }
}
EOF
)

DS_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "${AUTH_HEADER}" \
  -H "${CONTENT_HEADER}" \
  -d "${DATASOURCE_PAYLOAD}" \
  "${GRAFANA_API}/datasources")

DS_HTTP_CODE=$(echo "${DS_RESPONSE}" | tail -1)
DS_BODY=$(echo "${DS_RESPONSE}" | head -1)

if [ "${DS_HTTP_CODE}" = "200" ] || [ "${DS_HTTP_CODE}" = "409" ]; then
  echo "PASS: Athena data source created (HTTP ${DS_HTTP_CODE})"
  if [ "${DS_HTTP_CODE}" = "409" ]; then
    echo "      (409 = already exists, skipping)"
  fi
else
  echo "FAIL: Could not create data source (HTTP ${DS_HTTP_CODE})"
  echo "      Response: ${DS_BODY}"
  exit 1
fi
echo ""

# ── Step 3: Import dashboards ────────────────────────────────────────────────
echo "--- Step 3: Import dashboards ---"

DASHBOARD_FILES=(
  "web-vitals.json"
  "error-monitoring.json"
  "traffic-overview.json"
)

for DASHBOARD_FILE in "${DASHBOARD_FILES[@]}"; do
  DASHBOARD_PATH="${DASHBOARDS_DIR}/${DASHBOARD_FILE}"
  if [ ! -f "${DASHBOARD_PATH}" ]; then
    echo "FAIL: Dashboard file not found: ${DASHBOARD_PATH}"
    exit 1
  fi

  DASHBOARD_TITLE=$(python3 -c "import json,sys; d=json.load(open('${DASHBOARD_PATH}')); print(d['title'])")

  IMPORT_PAYLOAD=$(cat <<EOF
{
  "dashboard": $(cat "${DASHBOARD_PATH}"),
  "overwrite": true,
  "folderId": 0,
  "inputs": []
}
EOF
)

  IMPORT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "${AUTH_HEADER}" \
    -H "${CONTENT_HEADER}" \
    -d "${IMPORT_PAYLOAD}" \
    "${GRAFANA_API}/dashboards/import")

  IMPORT_HTTP_CODE=$(echo "${IMPORT_RESPONSE}" | tail -1)
  IMPORT_BODY=$(echo "${IMPORT_RESPONSE}" | head -1)

  if [ "${IMPORT_HTTP_CODE}" = "200" ]; then
    DASHBOARD_URL=$(echo "${IMPORT_BODY}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('importedUrl', 'unknown'))" 2>/dev/null || echo "unknown")
    echo "PASS: Imported '${DASHBOARD_TITLE}'"
    echo "      URL: ${GRAFANA_URL}${DASHBOARD_URL}"
  else
    echo "FAIL: Could not import '${DASHBOARD_TITLE}' (HTTP ${IMPORT_HTTP_CODE})"
    echo "      Response: ${IMPORT_BODY}"
    exit 1
  fi
done

echo ""
echo "=== Provisioning complete ==="
echo ""
echo "Open Grafana: ${GRAFANA_URL}"
echo "Dashboards are in the General folder."
echo ""
echo "Next: Run the RUM simulator to generate data, then refresh the dashboards."
echo "  python3 scripts/rum-simulator.py --endpoint \$(cd terraform && terraform output -raw api_endpoint) --count 100"
