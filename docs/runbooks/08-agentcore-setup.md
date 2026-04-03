# 런북: Bedrock AgentCore 에이전트 셋업

## 개요
RUM 분석 AI 에이전트 (Bedrock AgentCore) 전체 구성 절차.
IAM → ECR → Memory → Gateway → Runtime → Endpoint 순서.

## 사전 조건
- Bedrock AgentCore 서비스 활성화 (ap-northeast-2)
- Docker (arm64 빌드 가능)
- `scripts/setup-agentcore.sh` 참조

## 절차

```bash
# 전체 자동 셋업 (권장)
bash scripts/setup-agentcore.sh
```

### 수동 절차 (단계별)

```bash
REGION=ap-northeast-2
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# 1. ECR 리포지토리 + Docker 이미지
aws ecr create-repository --repository-name rum-agent --region ${REGION}
cd agentcore
docker build --platform linux/arm64 -t rum-agent .
docker tag rum-agent:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/rum-agent:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/rum-agent:latest

# 2. AgentCore Memory (대화 히스토리 저장)
aws bedrock-agentcore create-memory \
  --name rum_analysis_memory \
  --region ${REGION}

# 3. AgentCore Gateway + Lambda 타겟 (Athena 쿼리)
# Athena Query Lambda가 이미 배포되어 있어야 함
aws bedrock-agentcore create-gateway \
  --name rum-athena-gw \
  --region ${REGION}

# 4. AgentCore Runtime + Endpoint
aws bedrock-agentcore create-runtime \
  --name rumAnalysisAgent \
  --region ${REGION}
```

## Agent UI 접근

```bash
# CloudFront URL 확인
cd terraform && terraform output agent_ui_cloudfront_url
# 또는 AWS 콘솔에서 CloudFront 배포 확인
```

## 검증

```bash
# Agent UI 채팅에서 테스트 질문:
# "오늘 웹 페이지뷰 수를 알려줘"
# → SQL 생성 → Athena 실행 → 결과 분석 흐름 확인
```

## 트러블슈팅

| 증상 | 원인 | 해결 |
|------|------|------|
| 채팅 응답 없음 | Bedrock 모델 접근 권한 | EC2 IAM 역할에 bedrock:InvokeModel 확인 |
| SQL 실행 실패 | Athena Query Lambda 에러 | Lambda 로그 확인, 워크그룹 설정 확인 |
| Memory 에러 | AgentCore Memory 미생성 | `aws bedrock-agentcore list-memories` 확인 |
