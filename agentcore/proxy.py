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


# CloudFront는 ~4KB 이하의 응답을 버퍼링함. 패딩으로 즉시 플러시 유도.
_PADDING = b": " + b"x" * 4000 + b"\n\n"


def _sse(data: dict) -> bytes:
    """SSE 이벤트 + 4KB 패딩 (CloudFront 버퍼 플러시)."""
    event = f"data: {json.dumps(data, ensure_ascii=False)}\n\n".encode()
    return event + _PADDING


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
        yield _sse({"type": "start"})
        yield _sse({"type": "status", "content": "\U0001f50d AgentCore Runtime 연결 중..."})

        # invoke를 스레드에서 실행 + 대기 중 진행 상태 표시
        loop = asyncio.get_event_loop()
        future = loop.run_in_executor(_executor, _invoke_runtime, payload_bytes)

        elapsed = 0
        PROGRESS_MSGS = [
            (5,  "\u2699\ufe0f 에이전트 초기화 중... (대화 히스토리 로드)"),
            (15, "\U0001f9e0 Claude Sonnet 4.6 모델 추론 중..."),
            (30, "\U0001f4ca 도구 실행 중... (Athena SQL 생성/실행)"),
            (50, "\u23f3 분석 데이터 수집 중... 잠시만 기다려주세요."),
            (70, "\U0001f4dd 결과 정리 중..."),
        ]
        msg_idx = 0
        last_hb = time.time()

        while not future.done():
            elapsed += 0.5

            # 단계별 진행 메시지
            if msg_idx < len(PROGRESS_MSGS) and elapsed >= PROGRESS_MSGS[msg_idx][0]:
                yield _sse({"type": "status", "content": PROGRESS_MSGS[msg_idx][1]})
                msg_idx += 1

            # 15초 간격 heartbeat (SSE 주석 — 연결 유지용)
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

        yield _sse({"type": "status", "content": "\U0001f4e1 AgentCore 응답 수신 중..."})

        try:
            body_stream = resp.get("response")  # StreamingBody
            if body_stream:
                for chunk in body_stream.iter_chunks(chunk_size=4096):
                    if chunk:
                        yield chunk + _PADDING
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
