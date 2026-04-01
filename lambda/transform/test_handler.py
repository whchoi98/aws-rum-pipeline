import json
import base64
import pytest


def _make_record(data, record_id="rec-001"):
    """Helper: wrap a dict as a Firehose input record."""
    encoded = base64.b64encode(json.dumps(data).encode("utf-8")).decode("utf-8")
    return {"recordId": record_id, "data": encoded}


def _decode_record(record):
    """Helper: decode a Firehose output record's data field."""
    return json.loads(base64.b64decode(record["data"]).decode("utf-8"))


VALID_EVENT = {
    "session_id": "sess-abc-123",
    "user_id": "user-hash-456",
    "device_id": "dev-789",
    "timestamp": 1743465600000,  # 2025-04-01 00:00:00 UTC
    "platform": "web",
    "app_version": "2.1.0",
    "event_type": "performance",
    "event_name": "lcp",
    "payload": {"value": 2500, "rating": "good"},
    "context": {
        "url": "/products/123",
        "device": {"os": "macOS", "browser": "Chrome 120"},
    },
}


class TestSchemaValidation:
    def test_valid_event_returns_ok(self):
        from handler import handler

        event = {"records": [_make_record(VALID_EVENT)]}
        result = handler(event, None)
        assert len(result["records"]) == 1
        assert result["records"][0]["result"] == "Ok"

    def test_missing_required_field_returns_processing_failed(self):
        from handler import handler

        incomplete = {k: v for k, v in VALID_EVENT.items() if k != "session_id"}
        event = {"records": [_make_record(incomplete)]}
        result = handler(event, None)
        assert result["records"][0]["result"] == "ProcessingFailed"

    def test_invalid_json_returns_processing_failed(self):
        from handler import handler

        bad_record = {
            "recordId": "rec-bad",
            "data": base64.b64encode(b"not json").decode("utf-8"),
        }
        result = handler({"records": [bad_record]}, None)
        assert result["records"][0]["result"] == "ProcessingFailed"


class TestPartitionKeys:
    def test_partition_keys_extracted_from_timestamp(self):
        from handler import handler

        event = {"records": [_make_record(VALID_EVENT)]}
        result = handler(event, None)
        rec = result["records"][0]
        keys = rec["metadata"]["partitionKeys"]
        assert keys["platform"] == "web"
        assert keys["year"] == "2025"
        assert keys["month"] == "04"
        assert keys["day"] == "01"
        assert keys["hour"] == "00"

    def test_partition_keys_for_mobile_platform(self):
        from handler import handler

        mobile_event = {**VALID_EVENT, "platform": "ios"}
        event = {"records": [_make_record(mobile_event)]}
        result = handler(event, None)
        keys = result["records"][0]["metadata"]["partitionKeys"]
        assert keys["platform"] == "ios"


class TestPiiStripping:
    def test_ip_removed_from_root(self):
        from handler import handler

        event_with_ip = {**VALID_EVENT, "ip": "1.2.3.4"}
        event = {"records": [_make_record(event_with_ip)]}
        result = handler(event, None)
        data = _decode_record(result["records"][0])
        assert "ip" not in data

    def test_ip_removed_from_context(self):
        from handler import handler

        event_with_ip = {
            **VALID_EVENT,
            "context": {**VALID_EVENT["context"], "ip": "1.2.3.4"},
        }
        event = {"records": [_make_record(event_with_ip)]}
        result = handler(event, None)
        data = _decode_record(result["records"][0])
        assert "ip" not in data.get("context", {})


class TestBatchProcessing:
    def test_multiple_records_processed_independently(self):
        from handler import handler

        good = _make_record(VALID_EVENT, "rec-good")
        bad = _make_record({"incomplete": True}, "rec-bad")
        result = handler({"records": [good, bad]}, None)

        results_map = {r["recordId"]: r["result"] for r in result["records"]}
        assert results_map["rec-good"] == "Ok"
        assert results_map["rec-bad"] == "ProcessingFailed"
