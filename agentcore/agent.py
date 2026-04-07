"""
RUM Analysis Agent — AgentCore Runtime + Memory + Gateway (MCP)

awsops 패턴을 따라 MCP Gateway를 통해 Athena Query Lambda에 접근합니다.
"""

import os
import json
import logging
import boto3

from bedrock_agentcore.runtime import BedrockAgentCoreApp
from bedrock_agentcore.memory import MemoryClient
from botocore.session import Session as BotocoreSession
from strands import Agent
from strands.hooks import AgentInitializedEvent, HookProvider, MessageAddedEvent
from strands.tools.mcp import MCPClient

from streamable_http_sigv4 import streamablehttp_client_with_sigv4

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ─── Config ───────────────────────────────────────────────────────────────────
REGION = os.getenv("AWS_REGION", "ap-northeast-2")
MEMORY_ID = os.getenv("MEMORY_ID", "")
GATEWAY_URL = os.getenv("GATEWAY_URL", "")  # MCP Gateway endpoint

app = BedrockAgentCoreApp()
memory_client = MemoryClient(region_name=REGION) if MEMORY_ID else None

# ─── System Prompt ────────────────────────────────────────────────────────────
SYSTEM_PROMPT = """당신은 RUM (Real User Monitoring) 데이터 분석 전문가입니다.

## 역할
- 관리자의 자연어 질문을 분석하여 Athena SQL 쿼리를 생성하고 실행합니다
- 쿼리 결과를 한국어로 알기 쉽게 해석하고 인사이트를 제공합니다
- 추가 분석이 필요하면 자동으로 드릴다운 쿼리를 실행합니다

## RUM 데이터 스키마
데이터베이스: rum_pipeline_db
테이블: rum_events

컬럼:
- session_id (string): 세션 ID
- user_id (string): 사용자 ID ('anonymous' 또는 'user_xxx')
- device_id (string): 디바이스 ID
- timestamp (bigint): Unix timestamp (밀리초)
- app_version (string): 앱 버전
- event_type (string): 'performance' | 'action' | 'error' | 'navigation' | 'resource'
- event_name (string): 이벤트 이름
  - performance: 'lcp', 'cls', 'inp', 'app_start', 'screen_load', 'frame_drop'
  - navigation: 'page_view', 'route_change', 'screen_view', 'screen_transition'
  - resource: 'fetch', 'xhr'
  - error: 'js_error', 'unhandled_rejection', 'crash', 'anr', 'oom'
  - action: 'click', 'scroll', 'tap', 'swipe'
- payload (string, JSON): json_extract_scalar(payload, '$.key')로 접근
  - performance: $.value (숫자), $.rating ('good'|'needs-improvement'|'poor')
  - error: $.message, $.stack, $.filename, $.lineno
  - resource: $.url, $.duration, $.transferSize, $.status
- context (string, JSON): json_extract_scalar(context, '$.key')로 접근
  - $.url, $.screen_name, $.device.os, $.device.browser, $.device.model
  - $.connection.type, $.connection.rtt

파티션 컬럼 (비용 절감 위해 반드시 WHERE에 포함):
- platform: 'web' | 'ios' | 'android'
- year, month, day, hour (모두 string)

## SQL 작성 규칙
1. 반드시 year, month, day 파티션 필터를 포함 (오늘: year='2026', month='04', day='03')
2. JSON 접근: json_extract_scalar(payload, '$.value')
3. 타임스탬프: from_unixtime(timestamp/1000)
4. 필요한 컬럼만 SELECT, LIMIT 사용
5. 테이블명: rum_pipeline_db.rum_events

## 응답 형식
1. 쿼리 결과를 표로 정리
2. 핵심 인사이트 2-3줄 요약
3. 개선 제안 (있으면)
4. 항상 한국어로 응답

## Decision Patterns
| 질문 유형 | 쿼리 전략 |
|-----------|-----------|
| 오늘 현황 | COUNT, DISTINCT session_id, error rate |
| 성능 분석 | approx_percentile for LCP/CLS/INP, GROUP BY page |
| 에러 분석 | WHERE event_type='error', GROUP BY message |
| 플랫폼 비교 | GROUP BY platform |
| 일간 비교 | day='오늘' vs day='어제' |
| 사용자 분석 | DISTINCT user_id, session patterns |
"""


# ─── Memory Hook ──────────────────────────────────────────────────────────────
class MemoryHook(HookProvider):
    def on_agent_initialized(self, event):
        if not MEMORY_ID or not memory_client:
            return
        try:
            turns = memory_client.get_last_k_turns(
                memory_id=MEMORY_ID,
                actor_id="user",
                session_id=event.agent.state.get("session_id", "default"),
                k=5,
            )
            if turns:
                ctx = "\n".join(
                    f"{m['role']}: {m['content']['text']}" for t in turns for m in t
                )
                event.agent.system_prompt += f"\n\n이전 대화:\n{ctx}"
        except Exception as e:
            logger.warning(f"Memory load failed: {e}")

    def on_message_added(self, event):
        if not MEMORY_ID or not memory_client:
            return
        try:
            msg = event.agent.messages[-1]
            memory_client.create_event(
                memory_id=MEMORY_ID,
                actor_id="user",
                session_id=event.agent.state.get("session_id", "default"),
                messages=[(str(msg["content"]), msg["role"])],
            )
        except Exception as e:
            logger.warning(f"Memory save failed: {e}")

    def register_hooks(self, registry):
        registry.add_callback(AgentInitializedEvent, self.on_agent_initialized)
        registry.add_callback(MessageAddedEvent, self.on_message_added)


# ─── Gateway Transport (SigV4) ───────────────────────────────────────────────
def create_gateway_transport(gateway_url: str):
    """Create SigV4-signed MCP transport for AgentCore Gateway."""
    session = BotocoreSession()
    credentials = session.get_credentials().get_frozen_credentials()
    return streamablehttp_client_with_sigv4(
        url=gateway_url,
        credentials=credentials,
        service="bedrock-agentcore",
        region=REGION,
        timeout=60,
        sse_read_timeout=300,
    )


# ─── Agent Factory ────────────────────────────────────────────────────────────
def create_agent(session_id: str = "default") -> Agent:
    """Create Strands agent with MCP Gateway tools or direct Lambda fallback."""
    tools = []
    model_id = f"{REGION}.anthropic.claude-sonnet-4-6-20250627-v1:0"

    if GATEWAY_URL:
        logger.info(f"Connecting to Gateway: {GATEWAY_URL}")
        mcp_client = MCPClient(lambda: create_gateway_transport(GATEWAY_URL))
        tools = mcp_client.list_tools_sync()
        logger.info(f"Discovered {len(tools)} tools from Gateway")
    else:
        logger.info("No GATEWAY_URL set — using direct Lambda invocation")
        # Fallback: direct Lambda tool
        lambda_client = boto3.client("lambda", region_name=REGION)
        athena_lambda = os.getenv("ATHENA_LAMBDA", "rum-pipeline-athena-query")

        @tool
        def query_athena(sql: str) -> str:
            """RUM 데이터를 분석하기 위해 Athena SQL 쿼리를 실행합니다."""
            resp = lambda_client.invoke(
                FunctionName=athena_lambda,
                Payload=json.dumps({"input": {"sql": sql}}),
            )
            return resp["Payload"].read().decode()

        tools = [query_athena]

    hooks = [MemoryHook()] if MEMORY_ID else []

    return Agent(
        model=model_id,
        system_prompt=SYSTEM_PROMPT,
        tools=tools,
        hooks=hooks,
        state={"session_id": session_id},
    )


# ─── Entrypoint ──────────────────────────────────────────────────────────────
@app.entrypoint
def invoke(payload, context):
    session_id = getattr(context, "session_id", "default")
    user_message = payload.get("prompt", "오늘 RUM 현황을 알려주세요")

    logger.info(f"[{session_id}] User: {user_message[:100]}")

    agent = create_agent(session_id)
    response = agent(user_message)

    result_text = response.message["content"][0]["text"]
    logger.info(f"[{session_id}] Response: {result_text[:100]}...")

    return {"result": result_text}


if __name__ == "__main__":
    app.run()
