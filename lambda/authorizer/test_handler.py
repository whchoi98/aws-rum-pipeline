# lambda/authorizer/test_handler.py
import json
import os
import time
from unittest.mock import patch, MagicMock
import pytest

os.environ["SSM_PARAMETER_NAME"] = "/rum-pipeline/dev/api-keys"
os.environ.setdefault("AWS_DEFAULT_REGION", "us-east-1")


def _make_event(api_key=None):
    """Helper: build a minimal HTTP API v2 authorizer request event."""
    headers = {"content-type": "application/json"}
    if api_key is not None:
        headers["x-api-key"] = api_key
    return {
        "version": "2.0",
        "type": "REQUEST",
        "routeArn": "arn:aws:execute-api:ap-northeast-2:123456789:abc123/$default/POST/v1/events",
        "identitySource": api_key,
        "routeKey": "POST /v1/events",
        "headers": headers,
        "requestContext": {
            "accountId": "123456789",
            "apiId": "abc123",
            "http": {"method": "POST", "path": "/v1/events"},
            "stage": "$default",
            "time": "01/Apr/2026:00:00:00 +0000",
        },
    }


class TestAuthorizerAllow:
    @patch("handler.ssm")
    def test_valid_key_returns_authorized(self, mock_ssm):
        import handler
        handler._key_cache = {"keys": None, "expires": 0}

        mock_ssm.get_parameter.return_value = {
            "Parameter": {"Value": "rum-dev-abc123,rum-dev-def456"}
        }
        event = _make_event("rum-dev-abc123")
        result = handler.handler(event, None)

        assert result["isAuthorized"] is True
        assert result["context"]["apiKeyId"] == "rum-dev-abc123"

    @patch("handler.ssm")
    def test_second_valid_key_returns_authorized(self, mock_ssm):
        import handler
        handler._key_cache = {"keys": None, "expires": 0}

        mock_ssm.get_parameter.return_value = {
            "Parameter": {"Value": "rum-dev-abc123,rum-dev-def456"}
        }
        event = _make_event("rum-dev-def456")
        result = handler.handler(event, None)

        assert result["isAuthorized"] is True
        assert result["context"]["apiKeyId"] == "rum-dev-def456"


class TestAuthorizerDeny:
    @patch("handler.ssm")
    def test_invalid_key_returns_unauthorized(self, mock_ssm):
        import handler
        handler._key_cache = {"keys": None, "expires": 0}

        mock_ssm.get_parameter.return_value = {
            "Parameter": {"Value": "rum-dev-abc123"}
        }
        event = _make_event("wrong-key")
        result = handler.handler(event, None)

        assert result["isAuthorized"] is False

    def test_missing_header_returns_unauthorized(self):
        import handler
        handler._key_cache = {"keys": None, "expires": 0}

        event = _make_event(api_key=None)
        result = handler.handler(event, None)

        assert result["isAuthorized"] is False

    def test_empty_key_returns_unauthorized(self):
        import handler
        handler._key_cache = {"keys": None, "expires": 0}

        event = _make_event("")
        result = handler.handler(event, None)

        assert result["isAuthorized"] is False


class TestSsmCaching:
    @patch("handler.ssm")
    def test_second_call_uses_cache(self, mock_ssm):
        import handler
        handler._key_cache = {"keys": None, "expires": 0}

        mock_ssm.get_parameter.return_value = {
            "Parameter": {"Value": "rum-dev-abc123"}
        }
        event = _make_event("rum-dev-abc123")

        handler.handler(event, None)
        handler.handler(event, None)

        mock_ssm.get_parameter.assert_called_once()

    @patch("handler.ssm")
    @patch("handler.time")
    def test_cache_expires_after_ttl(self, mock_time, mock_ssm):
        import handler
        handler._key_cache = {"keys": None, "expires": 0}

        mock_ssm.get_parameter.return_value = {
            "Parameter": {"Value": "rum-dev-abc123"}
        }
        event = _make_event("rum-dev-abc123")

        mock_time.time.return_value = 1000.0
        handler.handler(event, None)

        mock_time.time.return_value = 1400.0
        handler.handler(event, None)

        assert mock_ssm.get_parameter.call_count == 2


class TestSsmFailure:
    @patch("handler.ssm")
    def test_ssm_error_returns_unauthorized(self, mock_ssm):
        import handler
        handler._key_cache = {"keys": None, "expires": 0}

        mock_ssm.get_parameter.side_effect = Exception("SSM unavailable")
        event = _make_event("rum-dev-abc123")
        result = handler.handler(event, None)

        assert result["isAuthorized"] is False
