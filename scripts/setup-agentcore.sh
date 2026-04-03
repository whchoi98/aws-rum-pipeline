#!/bin/bash
set -e
################################################################################
#                                                                              #
#   RUM AgentCore 전체 셋업                                                      #
#                                                                              #
#   Creates:                                                                   #
#     1. IAM Role (AgentCore - Bedrock + ECR + Lambda)                         #
#     2. ECR Repository + Docker image (arm64)                                 #
#     3. AgentCore Memory (대화 기록 + RUM 인사이트)                               #
#     4. AgentCore Gateway + Athena Query Lambda Target                        #
#     5. AgentCore Runtime + Endpoint                                          #
#                                                                              #
#   Based on: awsops/scripts/06a-setup-agentcore-runtime.sh pattern           #
#                                                                              #
################################################################################

GREEN='\033[0;32m'; RED='\033[0;31m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'
WORK_DIR="$(cd "$(dirname "$0")/.." && pwd)"
REGION="${AWS_DEFAULT_REGION:-ap-northeast-2}"
PREFIX="rum-agent"

run_or_fail() {
    local step_name="$1"; shift
    local output
    if ! output=$("$@" 2>&1); then
        echo -e "  ${RED}ERROR in ${step_name}:${NC}"
        echo "$output" | head -20
        exit 1
    fi
    echo "$output"
}

# -- Preflight ----------------------------------------------------------------
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text 2>&1) || {
    echo -e "${RED}ERROR: AWS 자격 증명을 사용할 수 없습니다${NC}"
    exit 1
}

echo ""
echo -e "${CYAN}=================================================================${NC}"
echo -e "${CYAN}   RUM AgentCore 셋업${NC}"
echo -e "${CYAN}=================================================================${NC}"
echo ""
echo "  Region:  $REGION"
echo "  Account: $ACCOUNT_ID"
echo ""

# =============================================================================
# [1/6] IAM Role
# =============================================================================
echo -e "${CYAN}[1/6] IAM 역할 생성...${NC}"

aws iam create-role --role-name RumAgentCoreRole \
    --assume-role-policy-document '{
        "Version": "2012-10-17",
        "Statement": [
            {"Effect": "Allow", "Principal": {"Service": "bedrock.amazonaws.com"}, "Action": "sts:AssumeRole"},
            {"Effect": "Allow", "Principal": {"Service": "bedrock-agentcore.amazonaws.com"}, "Action": "sts:AssumeRole"}
        ]
    }' 2>/dev/null || echo "  (이미 존재)"

aws iam attach-role-policy --role-name RumAgentCoreRole \
    --policy-arn arn:aws:iam::aws:policy/AmazonBedrockFullAccess 2>/dev/null || true

aws iam put-role-policy --role-name RumAgentCoreRole --policy-name RumAgentPermissions \
    --policy-document "{
        \"Version\": \"2012-10-17\",
        \"Statement\": [{
            \"Effect\": \"Allow\",
            \"Action\": [\"ecr:*\", \"lambda:InvokeFunction\", \"lambda:GetFunction\", \"bedrock-agentcore:*\",
                         \"athena:*\", \"s3:GetObject\", \"s3:PutObject\", \"s3:ListBucket\", \"s3:GetBucketLocation\",
                         \"glue:GetTable\", \"glue:GetDatabase\", \"glue:GetPartitions\"],
            \"Resource\": \"*\"
        }]
    }" 2>/dev/null || true

echo "  RumAgentCoreRole: OK"
echo "  IAM 전파 대기 (10초)..."
sleep 10

# =============================================================================
# [2/6] ECR + Docker Build (arm64)
# =============================================================================
echo ""
echo -e "${CYAN}[2/6] Docker 이미지 빌드 (arm64)...${NC}"

aws ecr create-repository --repository-name ${PREFIX} --region "$REGION" 2>/dev/null || echo "  (이미 존재)"
ECR_URI="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/${PREFIX}"

aws ecr get-login-password --region "$REGION" | \
    docker login --username AWS --password-stdin "${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com" 2>/dev/null

docker buildx create --use 2>/dev/null || true
echo "  빌드 중... (2-3분 소요)"
docker buildx build --platform linux/arm64 \
    -t "${ECR_URI}:latest" --push \
    "$WORK_DIR/agentcore/" 2>&1 | tail -5

echo "  이미지: ${ECR_URI}:latest (arm64)"

# =============================================================================
# [3/6] AgentCore Memory
# =============================================================================
echo ""
echo -e "${CYAN}[3/6] AgentCore Memory 생성...${NC}"

MEM_RESULT=$(aws bedrock-agentcore-control create-memory \
    --name "rum_analysis_memory" \
    --description "RUM 분석 에이전트 대화 기록 + 인사이트" \
    --event-expiry-duration 365 \
    --strategies '[{"semanticMemoryStrategy":{"name":"RumInsights","namespaces":["/rum/insights/"]}}]' \
    --region "$REGION" --output json 2>&1) || {
    echo -e "  ${YELLOW}Memory 이미 존재하거나 생성 실패${NC}"
    echo "$MEM_RESULT" | head -5
    MEM_RESULT="{}"
}

MEMORY_ID=$(echo "$MEM_RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('memoryId',''))" 2>/dev/null || echo "")
if [ -n "$MEMORY_ID" ]; then
    echo "  Memory ID: $MEMORY_ID"
    echo "  대기 중... (Active 될 때까지)"
    sleep 30
else
    echo "  기존 Memory 사용 또는 수동 설정 필요"
    MEMORY_ID=$(aws bedrock-agentcore-control list-memories --region "$REGION" \
        --query 'memories[?contains(name,`rum`)].memoryId | [0]' --output text 2>/dev/null || echo "")
    echo "  Memory ID: ${MEMORY_ID:-없음}"
fi

# =============================================================================
# [4/6] AgentCore Gateway + Lambda Target
# =============================================================================
echo ""
echo -e "${CYAN}[4/6] AgentCore Gateway 생성...${NC}"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/RumAgentCoreRole"

GW_RESULT=$(aws bedrock-agentcore-control create-gateway \
    --name "rum_athena_gateway" \
    --role-arn "$ROLE_ARN" \
    --protocol-type MCP \
    --region "$REGION" --output json 2>&1) || {
    echo -e "  ${YELLOW}Gateway 이미 존재하거나 생성 실패${NC}"
    echo "$GW_RESULT" | head -5
    GW_RESULT="{}"
}

GW_ID=$(echo "$GW_RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('gatewayId',''))" 2>/dev/null || echo "")
GW_URL=$(echo "$GW_RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('gatewayUrl',''))" 2>/dev/null || echo "")

if [ -z "$GW_ID" ]; then
    GW_ID=$(aws bedrock-agentcore-control list-gateways --region "$REGION" \
        --query 'gateways[?contains(name,`rum`)].gatewayId | [0]' --output text 2>/dev/null || echo "")
    GW_URL=$(aws bedrock-agentcore-control list-gateways --region "$REGION" \
        --query 'gateways[?contains(name,`rum`)].gatewayUrl | [0]' --output text 2>/dev/null || echo "")
fi

echo "  Gateway ID:  $GW_ID"
echo "  Gateway URL: $GW_URL"

if [ -n "$GW_ID" ]; then
    echo ""
    echo "  Lambda Target 추가..."
    LAMBDA_ARN="arn:aws:lambda:${REGION}:${ACCOUNT_ID}:function:rum-pipeline-athena-query"

    TOOL_SCHEMA='{"inlinePayload":[{"name":"query_athena","description":"RUM 데이터를 분석하기 위해 Athena SQL 쿼리를 실행합니다. rum_pipeline_db.rum_events 테이블을 조회합니다.","inputSchema":{"type":"object","properties":{"sql":{"type":"string","description":"실행할 Athena SQL 쿼리 (SELECT만 허용). 반드시 year/month/day 파티션 필터를 포함하세요."}},"required":["sql"]}}]}'

    aws bedrock-agentcore-control create-gateway-target \
        --gateway-identifier "$GW_ID" \
        --name "athena_query" \
        --description "Athena SQL 쿼리 실행 (RUM 데이터 분석)" \
        --target-configuration "{\"mcp\":{\"lambda\":{\"lambdaArn\":\"${LAMBDA_ARN}\",\"toolSchema\":${TOOL_SCHEMA}}}}" \
        --credential-provider-configurations '[{"credentialProviderType":"GATEWAY_IAM_ROLE"}]' \
        --region "$REGION" 2>&1 | head -5 || echo "  (이미 존재하거나 실패)"
fi

# =============================================================================
# [5/6] AgentCore Runtime
# =============================================================================
echo ""
echo -e "${CYAN}[5/6] AgentCore Runtime 생성...${NC}"
sleep 5

RT_RESULT=$(aws bedrock-agentcore-control create-agent-runtime \
    --agent-runtime-name rum_analysis_agent \
    --role-arn "$ROLE_ARN" \
    --agent-runtime-artifact "{\"containerConfiguration\":{\"containerUri\":\"${ECR_URI}:latest\"}}" \
    --network-configuration '{"networkMode":"PUBLIC"}' \
    --environment-variables "{\"MEMORY_ID\":\"${MEMORY_ID}\",\"GATEWAY_URL\":\"${GW_URL}\",\"AWS_REGION\":\"${REGION}\"}" \
    --region "$REGION" --output json 2>&1) || {
    echo -e "  ${RED}Runtime 생성 실패${NC}"
    echo "$RT_RESULT" | head -10
    RT_RESULT="{}"
}

RT_ID=$(echo "$RT_RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('agentRuntimeId',''))" 2>/dev/null || echo "")
RT_ARN=$(echo "$RT_RESULT" | python3 -c "import json,sys;print(json.load(sys.stdin).get('agentRuntimeArn',''))" 2>/dev/null || echo "")
echo "  Runtime ID:  $RT_ID"
echo "  Runtime ARN: $RT_ARN"

# =============================================================================
# [6/6] Runtime Endpoint
# =============================================================================
echo ""
echo -e "${CYAN}[6/6] Runtime Endpoint 생성...${NC}"

if [ -n "$RT_ID" ]; then
    EP_RESULT=$(aws bedrock-agentcore-control create-agent-runtime-endpoint \
        --agent-runtime-id "$RT_ID" --name rum_agent_endpoint \
        --region "$REGION" --output json 2>&1) || {
        echo -e "  ${RED}Endpoint 생성 실패${NC}"
        echo "$EP_RESULT" | head -10
        EP_RESULT="{}"
    }
    EP_ID=$(echo "$EP_RESULT" | python3 -c "import json,sys;d=json.load(sys.stdin);print(d.get('agentRuntimeEndpointId',d.get('endpointId','N/A')))" 2>/dev/null || echo "N/A")
    echo "  Endpoint ID: $EP_ID"
fi

# =============================================================================
# Summary
# =============================================================================
echo ""
echo -e "${GREEN}=================================================================${NC}"
echo -e "${GREEN}   RUM AgentCore 셋업 완료${NC}"
echo -e "${GREEN}=================================================================${NC}"
echo ""
echo "  IAM Role:     RumAgentCoreRole"
echo "  ECR Image:    ${ECR_URI}:latest (arm64)"
echo "  Memory ID:    ${MEMORY_ID:-N/A}"
echo "  Gateway ID:   ${GW_ID:-N/A}"
echo "  Gateway URL:  ${GW_URL:-N/A}"
echo "  Runtime ID:   ${RT_ID:-N/A}"
echo "  Runtime ARN:  ${RT_ARN:-N/A}"
echo "  Endpoint ID:  ${EP_ID:-N/A}"
echo ""
echo "  테스트:"
echo "    agentcore invoke '{\"prompt\": \"오늘 RUM 현황을 알려주세요\"}' -a rum_analysis_agent"
echo ""
