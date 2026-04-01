"""Thin Lambda forwarder: receives HTTP batch events, sends to Firehose."""

import json
import os
import base64
import boto3

firehose = boto3.client("firehose")
STREAM_NAME = os.environ["FIREHOSE_STREAM_NAME"]


def handler(event, context):
    body = event.get("body", "")
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")

    try:
        parsed = json.loads(body)
        events = parsed if isinstance(parsed, list) else [parsed]
    except (json.JSONDecodeError, TypeError):
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Invalid JSON"}),
        }

    records = [{"Data": (json.dumps(e) + "\n").encode("utf-8")} for e in events]

    # PutRecordBatch limit: 500 records per call
    for i in range(0, len(records), 500):
        batch = records[i : i + 500]
        firehose.put_record_batch(DeliveryStreamName=STREAM_NAME, Records=batch)

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({"status": "ok", "count": len(records)}),
    }
