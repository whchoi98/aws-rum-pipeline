"""Firehose transform Lambda: validates schema, strips PII, extracts partition keys."""

import json
import base64
from datetime import datetime, timezone

REQUIRED_FIELDS = ["session_id", "timestamp", "platform", "event_type", "event_name"]


def handler(event, context):
    output = []

    for record in event["records"]:
        record_id = record["recordId"]
        try:
            raw = base64.b64decode(record["data"]).decode("utf-8")
            data = json.loads(raw)

            # Schema validation
            missing = [f for f in REQUIRED_FIELDS if f not in data]
            if missing:
                output.append(
                    {
                        "recordId": record_id,
                        "result": "ProcessingFailed",
                        "data": record["data"],
                    }
                )
                continue

            # Extract timestamp for partitioning
            ts = data["timestamp"]
            if isinstance(ts, (int, float)):
                dt = datetime.fromtimestamp(ts / 1000, tz=timezone.utc)
            else:
                dt = datetime.fromisoformat(str(ts))

            # Strip PII — remove IP addresses
            data.pop("ip", None)
            ctx = data.get("context")
            if isinstance(ctx, dict):
                ctx.pop("ip", None)

            # Serialize payload and context to JSON strings for Parquet
            if "payload" in data and not isinstance(data["payload"], str):
                data["payload"] = json.dumps(data["payload"])
            if "context" in data and not isinstance(data["context"], str):
                data["context"] = json.dumps(data["context"])

            # Encode transformed data
            transformed = json.dumps(data) + "\n"
            encoded = base64.b64encode(transformed.encode("utf-8")).decode("utf-8")

            output.append(
                {
                    "recordId": record_id,
                    "result": "Ok",
                    "data": encoded,
                    "metadata": {
                        "partitionKeys": {
                            "platform": data["platform"],
                            "year": dt.strftime("%Y"),
                            "month": dt.strftime("%m"),
                            "day": dt.strftime("%d"),
                            "hour": dt.strftime("%H"),
                        }
                    },
                }
            )
        except (json.JSONDecodeError, KeyError, ValueError, TypeError):
            output.append(
                {
                    "recordId": record_id,
                    "result": "ProcessingFailed",
                    "data": record["data"],
                }
            )

    return {"records": output}
