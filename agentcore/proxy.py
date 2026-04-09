"""
AgentCore Runtime SSE Streaming Proxy

EC2에서 실행. Next.js route.ts의 HTTP 요청을 AgentCore Runtime SSE 스트리밍으로 중계.
route.ts → POST localhost:8080/invocations → invoke_agent_runtime → iter_lines → SSE 실시간 전달
"""

import json
import os
import logging

import boto3
from starlette.applications import Starlette
from starlette.routing import Route
from starlette.requests import Request
from starlette.responses import StreamingResponse, JSONResponse
import uvicorn

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REGION = os.getenv("AWS_REGION", "ap-northeast-2")
ENDPOINT_ARN = os.getenv("AGENTCORE_ENDPOINT_ARN", "")

# ARN 파싱: runtime ARN + endpoint name 분리
_parts = ENDPOINT_ARN.split("/runtime-endpoint/")
RUNTIME_ARN = _parts[0] if _parts else ""
ENDPOINT_NAME = _parts[1] if len(_parts) > 1 else None

agentcore_client = boto3.client("bedrock-agentcore", region_name=REGION)

logger.info(f"Runtime ARN: {RUNTIME_ARN}")
logger.info(f"Endpoint: {ENDPOINT_NAME}")

# CloudFront ~4KB 버퍼 플러시용 패딩 (SSE 주석 — 클라이언트가 무시)
_PADDING = b": " + b"x" * 4000 + b"\n\n"


async def handle_invocation(request: Request):
    """route.ts → AgentCore Runtime SSE 실시간 중계."""
    body = await request.json()
    prompt = body.get("prompt", "")
    session_id = body.get("session_id", "default")

    if not prompt:
        return JSONResponse({"error": "prompt required"}, status_code=400)
    if not RUNTIME_ARN:
        return JSONResponse({"error": "AGENTCORE_ENDPOINT_ARN not set"}, status_code=500)

    payload = json.dumps({"prompt": prompt, "session_id": session_id}).encode()

    async def stream():
        try:
            kwargs = {"agentRuntimeArn": RUNTIME_ARN, "payload": payload}
            if ENDPOINT_NAME:
                kwargs["qualifier"] = ENDPOINT_NAME

            resp = agentcore_client.invoke_agent_runtime(**kwargs)

            status_code = resp.get("statusCode", 200)
            content_type = resp.get("contentType", "")
            logger.info(f"[{session_id}] statusCode={status_code} contentType={content_type}")

            if status_code != 200:
                yield f"data: {json.dumps({'type':'error','content':f'Runtime {status_code}'})}\n\n".encode() + _PADDING
                return

            body_stream = resp.get("response")
            if not body_stream:
                yield f"data: {json.dumps({'type':'error','content':'Empty response'})}\n\n".encode() + _PADDING
                return

            # SSE 실시간 스트리밍: iter_lines(chunk_size=10)로 줄 단위 즉시 전달
            for line in body_stream.iter_lines(chunk_size=10):
                if line:
                    yield line + b"\n\n" + _PADDING

        except Exception as e:
            logger.error(f"[{session_id}] Error: {e}")
            yield f"data: {json.dumps({'type':'error','content':str(e)})}\n\n".encode() + _PADDING

    return StreamingResponse(stream(), media_type="text/event-stream")


async def handle_ping(request: Request):
    """헬스체크."""
    return JSONResponse({"status": "Healthy", "runtime_arn": RUNTIME_ARN})


app = Starlette(routes=[
    Route("/invocations", handle_invocation, methods=["POST"]),
    Route("/ping", handle_ping, methods=["GET"]),
])

if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=8080)
