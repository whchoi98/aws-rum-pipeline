import json
import base64
import os
from unittest.mock import patch, MagicMock
import pytest

# Set env before import
os.environ["FIREHOSE_STREAM_NAME"] = "test-stream"
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")


class TestIngestHandler:
    @patch("handler.firehose")
    def test_batch_events_forwarded_to_firehose(self, mock_firehose):
        from handler import handler

        mock_firehose.put_record_batch.return_value = {"FailedPutCount": 0}
        events = [
            {"session_id": "s1", "event_type": "performance", "event_name": "lcp"},
            {"session_id": "s2", "event_type": "action", "event_name": "click"},
        ]
        api_event = {"body": json.dumps(events), "isBase64Encoded": False}
        result = handler(api_event, None)

        assert result["statusCode"] == 200
        body = json.loads(result["body"])
        assert body["count"] == 2
        mock_firehose.put_record_batch.assert_called_once()
        call_args = mock_firehose.put_record_batch.call_args
        assert call_args.kwargs["DeliveryStreamName"] == "test-stream"
        assert len(call_args.kwargs["Records"]) == 2

    @patch("handler.firehose")
    def test_single_event_wrapped_as_list(self, mock_firehose):
        from handler import handler

        mock_firehose.put_record_batch.return_value = {"FailedPutCount": 0}
        single = {"session_id": "s1", "event_type": "action", "event_name": "click"}
        api_event = {"body": json.dumps(single), "isBase64Encoded": False}
        result = handler(api_event, None)

        assert result["statusCode"] == 200
        assert json.loads(result["body"])["count"] == 1

    def test_invalid_json_returns_400(self):
        from handler import handler

        api_event = {"body": "not-json{", "isBase64Encoded": False}
        result = handler(api_event, None)
        assert result["statusCode"] == 400

    @patch("handler.firehose")
    def test_base64_encoded_body_decoded(self, mock_firehose):
        from handler import handler

        mock_firehose.put_record_batch.return_value = {"FailedPutCount": 0}
        events = [{"session_id": "s1", "event_type": "action", "event_name": "tap"}]
        encoded_body = base64.b64encode(json.dumps(events).encode("utf-8")).decode(
            "utf-8"
        )
        api_event = {"body": encoded_body, "isBase64Encoded": True}
        result = handler(api_event, None)

        assert result["statusCode"] == 200
        assert json.loads(result["body"])["count"] == 1

    @patch("handler.firehose")
    def test_large_batch_split_into_500_chunks(self, mock_firehose):
        from handler import handler

        mock_firehose.put_record_batch.return_value = {"FailedPutCount": 0}
        events = [{"session_id": f"s{i}", "event_type": "action", "event_name": "click"} for i in range(750)]
        api_event = {"body": json.dumps(events), "isBase64Encoded": False}
        result = handler(api_event, None)

        assert result["statusCode"] == 200
        assert mock_firehose.put_record_batch.call_count == 2
