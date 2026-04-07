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
from strands import Agent, tool
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
| 에러 분석 | WHERE event_type='error', GROUP BY message → CloudWatch 로그 교차 분석 |
| 플랫폼 비교 | GROUP BY platform |
| 일간 비교 | day='오늘' vs day='어제' |
| 사용자 분석 | DISTINCT user_id, session patterns |
| 인프라 상태 | describe_alarms → 활성 알람 확인 |
| 근본 원인 | Athena 에러 집계 → search_logs로 Lambda 에러 로그 확인 |

## 추가 도구
Athena SQL 외에도 다음 도구를 사용할 수 있습니다:
- search_logs: CloudWatch 로그 그룹에서 패턴 검색 (에러 로그 분석)
- get_metrics: CloudWatch 메트릭 조회 (API 응답시간, Lambda 에러율 등)
- describe_alarms: 활성 알람 상태 확인
- select_s3_object: S3에서 직접 raw 이벤트 조회 (Athena 비용 절감)
- get_table_schema: Glue 테이블 스키마 확인
- create_grafana_annotation: Grafana 대시보드에 이벤트 어노테이션 등록
- publish_sns: 분석 결과를 SNS 토픽으로 발송

## 도구 사용 규칙 (중요!)
1. 한 번에 최대 2개 도구만 호출하세요. 모든 도구를 한꺼번에 사용하지 마세요.
2. 첫 호출에서 핵심 데이터를 확인하고, 부족하면 추가 도구를 사용하세요.
3. 질문과 무관한 도구는 호출하지 마세요.

질문별 가이드:
- 에러 분석 → query_athena 먼저, 필요시 search_logs 추가
- 성능 분석 → query_athena 먼저, 필요시 get_metrics 추가
- 인프라 상태 → describe_alarms 먼저, 필요시 get_metrics 추가
- 스키마 확인 → get_table_schema만
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


# ─── Direct Tools (boto3) ────────────────────────────────────────────────────
PROJECT_NAME = os.getenv("PROJECT_NAME", "rum-pipeline")
SNS_TOPIC_ARN = os.getenv("SNS_TOPIC_ARN", "")
GRAFANA_URL = os.getenv("GRAFANA_URL", "")
GRAFANA_API_KEY = os.getenv("GRAFANA_API_KEY", "")
S3_RAW_BUCKET = os.getenv("S3_RAW_BUCKET", f"{PROJECT_NAME}-raw-events")


@tool
def search_logs(log_group: str, filter_pattern: str, minutes: int = 30) -> str:
    """CloudWatch 로그 그룹에서 패턴을 검색합니다. Lambda 에러 로그 분석에 사용합니다.
    log_group: 로그 그룹명 (예: /aws/lambda/rum-pipeline-ingest)
    filter_pattern: 검색 패턴 (예: ERROR, Timeout, Exception)
    minutes: 최근 N분 이내 (기본 30)"""
    import time as _time
    logs = boto3.client("logs", region_name=REGION)
    try:
        resp = logs.filter_log_events(
            logGroupName=log_group,
            filterPattern=filter_pattern,
            startTime=int((_time.time() - minutes * 60) * 1000),
            limit=20,
        )
        events = resp.get("events", [])
        if not events:
            return json.dumps({"message": f"최근 {minutes}분 내 '{filter_pattern}' 패턴 없음", "count": 0})
        results = [{"timestamp": e["timestamp"], "message": e["message"][:500]} for e in events]
        return json.dumps({"count": len(events), "events": results}, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def get_metrics(namespace: str, metric_name: str, dimensions: str = "", minutes: int = 60, stat: str = "Average") -> str:
    """CloudWatch 메트릭을 조회합니다. 파이프라인 성능/에러율 분석에 사용합니다.
    namespace: 메트릭 네임스페이스 (예: AWS/ApiGateway, AWS/Lambda, AWS/Firehose)
    metric_name: 메트릭명 (예: Latency, Errors, Duration, IncomingRecords)
    dimensions: 'Key=Value,Key=Value' 형식 (예: FunctionName=rum-pipeline-ingest)
    minutes: 조회 기간 (기본 60)
    stat: 통계 타입 (Average, Sum, Maximum, Minimum, p99)"""
    import time as _time
    from datetime import datetime, timezone
    cw = boto3.client("cloudwatch", region_name=REGION)
    try:
        dim_list = []
        if dimensions:
            for pair in dimensions.split(","):
                k, v = pair.strip().split("=", 1)
                dim_list.append({"Name": k.strip(), "Value": v.strip()})
        now = datetime.now(timezone.utc)
        start = datetime.fromtimestamp(_time.time() - minutes * 60, tz=timezone.utc)
        period = max(60, (minutes * 60) // 20)  # 최소 60초, 최대 20 데이터포인트
        resp = cw.get_metric_statistics(
            Namespace=namespace,
            MetricName=metric_name,
            Dimensions=dim_list,
            StartTime=start,
            EndTime=now,
            Period=period,
            Statistics=[stat] if stat in ("Average", "Sum", "Maximum", "Minimum", "SampleCount") else [],
            ExtendedStatistics=[stat] if stat.startswith("p") else [],
        )
        points = sorted(resp.get("Datapoints", []), key=lambda x: x["Timestamp"])
        data = [{"time": p["Timestamp"].isoformat(), "value": p.get(stat, p.get("ExtendedStatistics", {}).get(stat, 0))} for p in points]
        return json.dumps({"metric": f"{namespace}/{metric_name}", "stat": stat, "period_sec": period, "datapoints": data}, ensure_ascii=False, default=str)
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def describe_alarms(state_filter: str = "ALARM", prefix: str = "") -> str:
    """CloudWatch 알람 상태를 조회합니다. 파이프라인 건강 상태 점검에 사용합니다.
    state_filter: ALARM, INSUFFICIENT_DATA, OK, 또는 빈 문자열(전체)
    prefix: 알람 이름 접두사 필터 (예: rum-pipeline)"""
    cw = boto3.client("cloudwatch", region_name=REGION)
    try:
        params = {}
        if state_filter:
            params["StateValue"] = state_filter
        if prefix:
            params["AlarmNamePrefix"] = prefix
        resp = cw.describe_alarms(**params, MaxRecords=20)
        alarms = []
        for a in resp.get("MetricAlarms", []):
            alarms.append({
                "name": a["AlarmName"],
                "state": a["StateValue"],
                "reason": a.get("StateReason", "")[:200],
                "metric": f"{a.get('Namespace', '')}/{a.get('MetricName', '')}",
                "updated": a.get("StateUpdatedTimestamp", ""),
            })
        if not alarms:
            return json.dumps({"message": f"'{state_filter}' 상태의 알람 없음", "count": 0})
        return json.dumps({"count": len(alarms), "alarms": alarms}, ensure_ascii=False, default=str)
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def select_s3_object(key: str, expression: str, bucket: str = "") -> str:
    """S3 Select로 raw 이벤트 파일을 직접 쿼리합니다. Athena 비용 절감 및 특정 세션 조회에 사용합니다.
    key: S3 오브젝트 키 (예: raw/platform=web/year=2026/month=04/day=07/hour=12/data.parquet)
    expression: SQL 표현식 (예: SELECT * FROM s3object s WHERE s.session_id = 'abc' LIMIT 10)
    bucket: S3 버킷명 (기본: rum-pipeline-raw-events)"""
    s3 = boto3.client("s3", region_name=REGION)
    target_bucket = bucket or S3_RAW_BUCKET
    try:
        input_format = {"Parquet": {}} if key.endswith(".parquet") else {"JSON": {"Type": "LINES"}}
        resp = s3.select_object_content(
            Bucket=target_bucket,
            Key=key,
            Expression=expression,
            ExpressionType="SQL",
            InputSerialization=input_format,
            OutputSerialization={"JSON": {}},
        )
        records = []
        for event in resp["Payload"]:
            if "Records" in event:
                records.append(event["Records"]["Payload"].decode())
        return json.dumps({"data": "".join(records)[:5000], "bucket": target_bucket, "key": key})
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def get_table_schema(table_name: str, database: str = "rum_pipeline_db") -> str:
    """Glue 데이터 카탈로그에서 테이블 스키마를 조회합니다. 컬럼 확인 및 쿼리 작성 지원에 사용합니다.
    table_name: 테이블명 (예: rum_events, rum_hourly_metrics, rum_daily_summary)
    database: 데이터베이스명 (기본: rum_pipeline_db)"""
    glue = boto3.client("glue", region_name=REGION)
    try:
        resp = glue.get_table(DatabaseName=database, Name=table_name)
        table = resp["Table"]
        columns = [{"name": c["Name"], "type": c["Type"], "comment": c.get("Comment", "")}
                   for c in table["StorageDescriptor"]["Columns"]]
        partitions = [{"name": p["Name"], "type": p["Type"]} for p in table.get("PartitionKeys", [])]
        return json.dumps({
            "table": table_name, "database": database,
            "columns": columns, "partitions": partitions,
            "location": table["StorageDescriptor"].get("Location", ""),
            "format": table["StorageDescriptor"].get("InputFormat", ""),
        }, ensure_ascii=False)
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def create_grafana_annotation(text: str, tags: str = "agent,analysis", dashboard_id: int = 0) -> str:
    """Grafana 대시보드에 어노테이션을 생성합니다. 분석 결과를 대시보드에 기록할 때 사용합니다.
    text: 어노테이션 내용 (분석 요약 등)
    tags: 쉼표 구분 태그 (기본: agent,analysis)
    dashboard_id: 대시보드 ID (0이면 전역 어노테이션)"""
    import urllib.request
    if not GRAFANA_URL or not GRAFANA_API_KEY:
        return json.dumps({"error": "GRAFANA_URL 또는 GRAFANA_API_KEY 환경변수 미설정"})
    try:
        import time as _time
        payload = json.dumps({
            "text": text,
            "tags": [t.strip() for t in tags.split(",")],
            "time": int(_time.time() * 1000),
            **({"dashboardId": dashboard_id} if dashboard_id else {}),
        }).encode()
        req = urllib.request.Request(
            f"{GRAFANA_URL}/api/annotations",
            data=payload,
            headers={"Authorization": f"Bearer {GRAFANA_API_KEY}", "Content-Type": "application/json"},
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=10) as resp:
            return resp.read().decode()
    except Exception as e:
        return json.dumps({"error": str(e)})


@tool
def publish_sns(message: str, subject: str = "RUM 분석 리포트") -> str:
    """SNS 토픽으로 메시지를 발행합니다. 분석 결과를 이메일/Slack으로 발송할 때 사용합니다.
    message: 발송할 메시지 내용
    subject: 이메일 제목 (기본: RUM 분석 리포트)"""
    if not SNS_TOPIC_ARN:
        return json.dumps({"error": "SNS_TOPIC_ARN 환경변수 미설정"})
    sns = boto3.client("sns", region_name=REGION)
    try:
        resp = sns.publish(
            TopicArn=SNS_TOPIC_ARN,
            Subject=subject[:100],
            Message=message[:262144],  # SNS 최대 256KB
        )
        return json.dumps({"messageId": resp["MessageId"], "status": "발송 완료"})
    except Exception as e:
        return json.dumps({"error": str(e)})


# ─── All Direct Tools ────────────────────────────────────────────────────────
DIRECT_TOOLS = [search_logs, get_metrics, describe_alarms, select_s3_object,
                get_table_schema, create_grafana_annotation, publish_sns]


# ─── Agent Factory ────────────────────────────────────────────────────────────
def create_agent(session_id: str = "default") -> Agent:
    """Create Strands agent with MCP Gateway tools + direct tools."""
    tools = list(DIRECT_TOOLS)  # 항상 직접 도구 포함
    model_id = "global.anthropic.claude-sonnet-4-6"

    if GATEWAY_URL:
        logger.info(f"Connecting to Gateway: {GATEWAY_URL}")
        mcp_client = MCPClient(lambda: create_gateway_transport(GATEWAY_URL))
        gateway_tools = mcp_client.list_tools_sync()
        tools.extend(gateway_tools)
        logger.info(f"Discovered {len(gateway_tools)} Gateway tools + {len(DIRECT_TOOLS)} direct tools")
    else:
        logger.info("No GATEWAY_URL set — using direct Lambda + boto3 tools")
        # Athena는 Lambda 호출로 (Gateway 없을 때)
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

        tools.append(query_athena)

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
