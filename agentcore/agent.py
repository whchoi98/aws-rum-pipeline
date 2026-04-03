"""RUM Analysis Agent — AgentCore Runtime + Memory + Athena Gateway."""

import os
import json
import boto3
from bedrock_agentcore.runtime import BedrockAgentCoreApp
from bedrock_agentcore.memory import MemoryClient
from strands import Agent
from strands.hooks import AgentInitializedEvent, HookProvider, MessageAddedEvent

app = BedrockAgentCoreApp()

# Config
REGION = os.getenv("AWS_REGION", "ap-northeast-2")
MEMORY_ID = os.getenv("MEMORY_ID", "")
ATHENA_LAMBDA = os.getenv("ATHENA_LAMBDA", "rum-pipeline-athena-query")

memory_client = MemoryClient(region_name=REGION) if MEMORY_ID else None
lambda_client = boto3.client("lambda", region_name=REGION)

SYSTEM_PROMPT = """당신은 RUM (Real User Monitoring) 데이터 분석 전문가입니다.

## 역할
- 관리자의 자연어 질문을 분석하여 Athena SQL 쿼리를 생성합니다
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
- payload (string, JSON): 이벤트 페이로드 (json_extract_scalar로 접근)
  - performance: $.value (숫자), $.rating ('good'|'needs-improvement'|'poor')
  - error: $.message, $.stack, $.filename, $.lineno
  - resource: $.url, $.duration, $.transferSize, $.status
- context (string, JSON): 컨텍스트 정보
  - $.url: 페이지 URL
  - $.screen_name: 모바일 화면 이름
  - $.device.os: 운영체제
  - $.device.browser: 브라우저
  - $.device.model: 디바이스 모델
  - $.connection.type: 네트워크 유형 (4g, wifi, 3g)
  - $.connection.rtt: 네트워크 왕복 시간

파티션 컬럼 (WHERE 절에서 사용하면 스캔 비용 절감):
- platform (string): 'web' | 'ios' | 'android'
- year (string): '2026'
- month (string): '04'
- day (string): '03'
- hour (string): '00'~'23'

## SQL 작성 규칙
1. JSON 필드 접근: json_extract_scalar(payload, '$.value')
2. 타임스탬프 변환: from_unixtime(timestamp/1000)
3. 파티션 필터 필수: year, month, day 포함
4. 비용 절감: 필요한 컬럼만 SELECT
5. LIMIT 사용: 대량 결과 방지

## 응답 형식
1. 쿼리 실행 결과를 표 형태로 보여주세요
2. 핵심 인사이트를 2-3줄로 요약하세요
3. 개선 제안이 있으면 추가하세요
4. 항상 한국어로 응답하세요
"""


class MemoryHook(HookProvider):
    def on_agent_initialized(self, event):
        if not MEMORY_ID or not memory_client:
            return
        turns = memory_client.get_last_k_turns(
            memory_id=MEMORY_ID,
            actor_id="user",
            session_id=event.agent.state.get("session_id", "default"),
            k=5,
        )
        if turns:
            context = "\n".join(
                [f"{m['role']}: {m['content']['text']}" for t in turns for m in t]
            )
            event.agent.system_prompt += f"\n\n이전 대화:\n{context}"

    def on_message_added(self, event):
        if not MEMORY_ID or not memory_client:
            return
        msg = event.agent.messages[-1]
        memory_client.create_event(
            memory_id=MEMORY_ID,
            actor_id="user",
            session_id=event.agent.state.get("session_id", "default"),
            messages=[(str(msg["content"]), msg["role"])],
        )

    def register_hooks(self, registry):
        registry.add_callback(AgentInitializedEvent, self.on_agent_initialized)
        registry.add_callback(MessageAddedEvent, self.on_message_added)


def query_athena(sql: str) -> dict:
    """Execute Athena SQL query via Lambda and return results."""
    resp = lambda_client.invoke(
        FunctionName=ATHENA_LAMBDA,
        Payload=json.dumps({"input": {"sql": sql}}),
    )
    result = json.loads(resp["Payload"].read())
    return result


# Register Athena query as a tool
from strands.types.tools import ToolSpec, ToolResult

athena_tool_spec = ToolSpec(
    name="query_athena",
    description="RUM 데이터를 분석하기 위해 Athena SQL 쿼리를 실행합니다. rum_pipeline_db.rum_events 테이블을 조회합니다.",
    inputSchema={
        "type": "object",
        "properties": {
            "sql": {
                "type": "string",
                "description": "실행할 Athena SQL 쿼리 (SELECT만 허용)",
            }
        },
        "required": ["sql"],
    },
)


def athena_tool_handler(tool_use):
    sql = tool_use["input"]["sql"]
    result = query_athena(sql)
    return ToolResult(
        toolUseId=tool_use["toolUseId"],
        content=[{"text": json.dumps(result, ensure_ascii=False, default=str)}],
    )


agent = Agent(
    model=f"ap-northeast-2.anthropic.claude-sonnet-4-20250514-v1:0",
    system_prompt=SYSTEM_PROMPT,
    tools=[
        {"toolSpec": athena_tool_spec, "handler": athena_tool_handler},
    ],
    hooks=[MemoryHook()] if MEMORY_ID else [],
    state={"session_id": "default"},
)


@app.entrypoint
def invoke(payload, context):
    if hasattr(context, "session_id"):
        agent.state["session_id"] = context.session_id

    user_message = payload.get("prompt", "오늘 RUM 현황을 알려주세요")
    response = agent(user_message)

    return {"result": response.message["content"][0]["text"]}


if __name__ == "__main__":
    app.run()
