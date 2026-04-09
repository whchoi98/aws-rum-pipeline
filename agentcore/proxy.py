"""
AgentCore Runtime HTTP Proxy

EC2에서 실행. Next.js route.ts의 HTTP 요청을 AgentCore Runtime invoke API로 중계.
route.ts → POST localhost:8080/invocations → boto3 invoke-agent-runtime → SSE 스트림
"""

import json
import os
import logging
import time
import concurrent.futures

import boto3
from starlette.applications import Starlette
from starlette.routing import Route
from starlette.requests import Request
from starlette.responses import StreamingResponse, JSONResponse
import uvicorn
import asyncio

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

REGION = os.getenv("AWS_REGION", "ap-northeast-2")
ENDPOINT_ARN = os.getenv("AGENTCORE_ENDPOINT_ARN", "")

# ARN에서 runtime ARN 추출
# arn:aws:bedrock-agentcore:region:account:runtime/{id}/runtime-endpoint/{name}
_parts = ENDPOINT_ARN.split("/runtime-endpoint/")
RUNTIME_ARN = _parts[0] if _parts else ""
ENDPOINT_NAME = _parts[1] if len(_parts) > 1 else None

agentcore_client = boto3.client("bedrock-agentcore", region_name=REGION)
_executor = concurrent.futures.ThreadPoolExecutor(max_workers=4)

logger.info(f"Runtime ARN: {RUNTIME_ARN}")
logger.info(f"Endpoint: {ENDPOINT_NAME}")


def _invoke_runtime(payload_bytes):
    """동기 boto3 호출 (스레드에서 실행)."""
    kwargs = {
        "agentRuntimeArn": RUNTIME_ARN,
        "payload": payload_bytes,
    }
    if ENDPOINT_NAME:
        kwargs["qualifier"] = ENDPOINT_NAME
    return agentcore_client.invoke_agent_runtime(**kwargs)


async def handle_invocation(request: Request):
    """route.ts로부터 HTTP POST를 받아 AgentCore Runtime invoke API로 중계."""
    body = await request.json()
    prompt = body.get("prompt", "")
    session_id = body.get("session_id", "default")

    if not prompt:
        return JSONResponse({"error": "prompt required"}, status_code=400)

    if not RUNTIME_ARN:
        return JSONResponse({"error": "AGENTCORE_ENDPOINT_ARN not set"}, status_code=500)

    payload_bytes = json.dumps({"prompt": prompt, "session_id": session_id}).encode()

    async def stream():
        # 즉시 첫 이벤트 전송 → CloudFront 60초 타임아웃 방지
        yield b"data: {\"type\":\"start\"}\n\n"
        yield b"data: {\"type\":\"status\",\"content\":\"\\ud83d\\udd0d \\ubd84\\uc11d \\uc911... \\ub9ac\\ud3ec\\ud2b8\\ub97c \\uc0dd\\uc131\\uc911\\uc785\\ub2c8\\ub2e4.\"}\n\n"

        # invoke를 스레드에서 실행 + 대기 중 heartbeat
        loop = asyncio.get_event_loop()
        future = loop.run_in_executor(_executor, _invoke_runtime, payload_bytes)

        last_hb = time.time()
        while not future.done():
            now = time.time()
            if now - last_hb > 15:
                yield b": heartbeat\n\n"
                last_hb = now
            await asyncio.sleep(0.5)

        try:
            resp = future.result()
        except Exception as e:
            logger.error(f"[{session_id}] invoke 실패: {e}")
            error = json.dumps({"type": "error", "content": str(e)})
            yield f"data: {error}\n\n".encode()
            return

        status_code = resp.get("statusCode", 200)
        if status_code != 200:
            error = json.dumps({"type": "error", "content": f"Runtime returned {status_code}"})
            yield f"data: {error}\n\n".encode()
            return

        logger.info(f"[{session_id}] Streaming from Runtime...")

        try:
            body_stream = resp.get("response")  # StreamingBody
            if body_stream:
                for chunk in body_stream.iter_chunks(chunk_size=4096):
                    if chunk:
                        yield chunk
        except Exception as e:
            logger.error(f"[{session_id}] Stream error: {e}")
            error = json.dumps({"type": "error", "content": str(e)})
            yield f"data: {error}\n\n".encode()

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
