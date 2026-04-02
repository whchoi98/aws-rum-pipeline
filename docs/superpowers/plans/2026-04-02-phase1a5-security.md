# Phase 1a.5 Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Lambda Authorizer (API key validation) and WAF (rate limiting + bot control) to the RUM pipeline API endpoint.

**Architecture:** New `security` Terraform module creates WAF WebACL and Authorizer Lambda. Existing `api-gateway` module is modified to wire the authorizer to routes and associate the WAF. API keys are stored in SSM Parameter Store and cached in the Lambda.

**Tech Stack:** Terraform, Python 3.12, AWS WAFv2, Lambda Authorizer (HTTP API v2 REQUEST type), SSM Parameter Store

**Spec:** `docs/superpowers/specs/2026-04-02-phase1a5-security-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `lambda/authorizer/handler.py` | Lambda Authorizer — validates x-api-key header against SSM |
| `lambda/authorizer/test_handler.py` | Unit tests for authorizer |
| `terraform/modules/security/main.tf` | WAF WebACL + Authorizer Lambda + IAM + SSM Parameter |
| `terraform/modules/security/variables.tf` | Module input variables |
| `terraform/modules/security/outputs.tf` | Exports: authorizer ARN, WAF ACL ARN |

### Modified Files

| File | Changes |
|------|---------|
| `terraform/modules/api-gateway/main.tf` | Add authorizer resource, wire to routes, WAF association |
| `terraform/modules/api-gateway/variables.tf` | Add authorizer/WAF input variables |
| `terraform/modules/api-gateway/outputs.tf` | Add execution ARN output |
| `terraform/main.tf` | Add `security` module, pass outputs to `api_gateway` |
| `terraform/outputs.tf` | Add WAF ACL ARN output |
| `scripts/test-ingestion.sh` | Add x-api-key header to all curl calls, add auth rejection test |

---

## Task 1: Lambda Authorizer — Write Failing Tests

**Files:**
- Create: `lambda/authorizer/test_handler.py`

- [ ] **Step 1: Create test file with all test cases**

```python
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `cd lambda/authorizer && python -m pytest test_handler.py -v`
Expected: FAIL — `ModuleNotFoundError: No module named 'handler'`

- [ ] **Step 3: Commit test file**

```bash
git add lambda/authorizer/test_handler.py
git commit -m "test(authorizer): add unit tests for Lambda Authorizer handler"
```

---

## Task 2: Lambda Authorizer — Implementation

**Files:**
- Create: `lambda/authorizer/handler.py`
- Test: `lambda/authorizer/test_handler.py` (from Task 1)

- [ ] **Step 1: Implement the authorizer handler**

```python
# lambda/authorizer/handler.py
"""Lambda Authorizer: validates x-api-key header against SSM Parameter Store."""

import json
import logging
import os
import time

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm = boto3.client("ssm")
SSM_PARAMETER_NAME = os.environ["SSM_PARAMETER_NAME"]
CACHE_TTL_SECONDS = 300

_key_cache = {"keys": None, "expires": 0}


def _get_valid_keys():
    """Fetch valid API keys from SSM, with in-memory caching."""
    now = time.time()
    if _key_cache["keys"] is not None and now < _key_cache["expires"]:
        return _key_cache["keys"]

    resp = ssm.get_parameter(Name=SSM_PARAMETER_NAME, WithDecryption=True)
    raw = resp["Parameter"]["Value"]
    keys = {k.strip() for k in raw.split(",") if k.strip()}
    _key_cache["keys"] = keys
    _key_cache["expires"] = now + CACHE_TTL_SECONDS
    return keys


def handler(event, context):
    headers = event.get("headers", {})
    api_key = headers.get("x-api-key", "")

    if not api_key:
        logger.info("Denied: missing x-api-key header")
        return {"isAuthorized": False}

    try:
        valid_keys = _get_valid_keys()
    except Exception:
        logger.exception("Failed to fetch API keys from SSM")
        return {"isAuthorized": False}

    if api_key not in valid_keys:
        logger.info("Denied: invalid API key")
        return {"isAuthorized": False}

    return {
        "isAuthorized": True,
        "context": {"apiKeyId": api_key},
    }
```

- [ ] **Step 2: Run tests to verify all pass**

Run: `cd lambda/authorizer && python -m pytest test_handler.py -v`
Expected: 8 tests PASS

- [ ] **Step 3: Commit implementation**

```bash
git add lambda/authorizer/handler.py
git commit -m "feat(authorizer): implement Lambda Authorizer with SSM-backed API key validation"
```

---

## Task 3: Security Terraform Module

**Files:**
- Create: `terraform/modules/security/main.tf`
- Create: `terraform/modules/security/variables.tf`
- Create: `terraform/modules/security/outputs.tf`

- [ ] **Step 1: Create variables.tf**

```hcl
# terraform/modules/security/variables.tf
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
}

variable "rate_limit" {
  description = "WAF rate limit: max requests per 5-minute window per IP"
  type        = number
  default     = 2000
}

variable "lambda_source_dir" {
  description = "Path to the authorizer Lambda source directory"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Create main.tf with WAF WebACL**

```hcl
# terraform/modules/security/main.tf

# -----------------------------------------------------------------------------
# WAF WebACL
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "rum" {
  name        = "${var.project_name}-waf"
  scope       = "REGIONAL"
  description = "WAF for RUM pipeline API"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
    }
  }

  rule {
    name     = "bot-control"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"

        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level = "COMMON"
          }
        }
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bot-control"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
  }

  tags = merge(var.tags, { Component = "waf" })
}

# -----------------------------------------------------------------------------
# API Key in SSM Parameter Store
# -----------------------------------------------------------------------------

resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "api_keys" {
  name        = "/${var.project_name}/${var.environment}/api-keys"
  description = "Comma-separated valid API keys for RUM pipeline"
  type        = "SecureString"
  value       = random_password.api_key.result

  lifecycle {
    ignore_changes = [value]
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda Authorizer
# -----------------------------------------------------------------------------

data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  excludes    = ["test_handler.py", "__pycache__", ".pytest_cache"]
  output_path = "${path.module}/files/authorizer.zip"
}

resource "aws_iam_role" "authorizer_lambda" {
  name = "${var.project_name}-authorizer-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "authorizer_lambda_logs" {
  role       = aws_iam_role.authorizer_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "authorizer_ssm" {
  name = "${var.project_name}-authorizer-ssm-access"
  role = aws_iam_role.authorizer_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = aws_ssm_parameter.api_keys.arn
    }]
  })
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.project_name}-authorizer"
  role             = aws_iam_role.authorizer_lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256

  environment {
    variables = {
      SSM_PARAMETER_NAME = aws_ssm_parameter.api_keys.name
    }
  }

  tags = merge(var.tags, { Component = "authorizer" })
}

resource "aws_cloudwatch_log_group" "authorizer_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.authorizer.function_name}"
  retention_in_days = 14
  tags              = var.tags
}
```

- [ ] **Step 3: Create outputs.tf**

```hcl
# terraform/modules/security/outputs.tf
output "authorizer_invoke_arn" {
  description = "Authorizer Lambda invoke ARN"
  value       = aws_lambda_function.authorizer.invoke_arn
}

output "authorizer_function_name" {
  description = "Authorizer Lambda function name"
  value       = aws_lambda_function.authorizer.function_name
}

output "waf_acl_arn" {
  description = "WAF WebACL ARN"
  value       = aws_wafv2_web_acl.rum.arn
}

output "api_key_ssm_name" {
  description = "SSM parameter name containing API keys"
  value       = aws_ssm_parameter.api_keys.name
}

output "initial_api_key" {
  description = "Initial generated API key (retrieve from SSM after deploy)"
  value       = random_password.api_key.result
  sensitive   = true
}
```

- [ ] **Step 4: Validate Terraform syntax**

Run: `cd terraform && terraform fmt -recursive -check modules/security/`
Expected: All files formatted correctly (no output)

- [ ] **Step 5: Commit security module**

```bash
git add terraform/modules/security/
git commit -m "feat(security): add Terraform module for WAF WebACL and Lambda Authorizer"
```

---

## Task 4: API Gateway Module — Wire Authorizer and WAF

**Files:**
- Modify: `terraform/modules/api-gateway/variables.tf`
- Modify: `terraform/modules/api-gateway/main.tf`
- Modify: `terraform/modules/api-gateway/outputs.tf`

- [ ] **Step 1: Add new variables for authorizer and WAF**

Append to `terraform/modules/api-gateway/variables.tf`:

```hcl
variable "authorizer_invoke_arn" {
  description = "Lambda Authorizer invoke ARN"
  type        = string
  default     = null
}

variable "waf_acl_arn" {
  description = "WAF WebACL ARN to associate with API stage"
  type        = string
  default     = null
}

variable "authorizer_function_name" {
  description = "Lambda Authorizer function name (for invoke permission)"
  type        = string
  default     = null
}
```

- [ ] **Step 2: Add authorizer resource and wire routes in main.tf**

Add after the `aws_apigatewayv2_stage` resource in `terraform/modules/api-gateway/main.tf`:

```hcl
# -----------------------------------------------------------------------------
# Lambda Authorizer (conditional)
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_authorizer" "api_key" {
  count = var.authorizer_invoke_arn != null ? 1 : 0

  api_id                            = aws_apigatewayv2_api.rum.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = var.authorizer_invoke_arn
  authorizer_payload_format_version = "2.0"
  authorizer_result_ttl_in_seconds  = 300
  identity_sources                  = ["$request.header.x-api-key"]
  name                              = "${var.project_name}-api-key-authorizer"
}

# -----------------------------------------------------------------------------
# WAF Association (conditional)
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl_association" "api" {
  count = var.waf_acl_arn != null ? 1 : 0

  resource_arn = aws_apigatewayv2_stage.default.arn
  web_acl_arn  = var.waf_acl_arn
}

# -----------------------------------------------------------------------------
# Authorizer Lambda Permission (conditional)
# -----------------------------------------------------------------------------

resource "aws_lambda_permission" "authorizer_apigw" {
  count = var.authorizer_function_name != null ? 1 : 0

  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.authorizer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rum.execution_arn}/*/*"
}
```

- [ ] **Step 3: Update routes to use authorizer**

Replace the two route resources in `terraform/modules/api-gateway/main.tf`:

```hcl
resource "aws_apigatewayv2_route" "post_events" {
  api_id    = aws_apigatewayv2_api.rum.id
  route_key = "POST /v1/events"
  target    = "integrations/${aws_apigatewayv2_integration.ingest_lambda.id}"

  authorization_type = var.authorizer_invoke_arn != null ? "CUSTOM" : "NONE"
  authorizer_id      = var.authorizer_invoke_arn != null ? aws_apigatewayv2_authorizer.api_key[0].id : null
}

resource "aws_apigatewayv2_route" "post_beacon" {
  api_id    = aws_apigatewayv2_api.rum.id
  route_key = "POST /v1/events/beacon"
  target    = "integrations/${aws_apigatewayv2_integration.ingest_lambda.id}"

  authorization_type = var.authorizer_invoke_arn != null ? "CUSTOM" : "NONE"
  authorizer_id      = var.authorizer_invoke_arn != null ? aws_apigatewayv2_authorizer.api_key[0].id : null
}
```

- [ ] **Step 4: Add stage ARN and execution ARN outputs**

Append to `terraform/modules/api-gateway/outputs.tf`:

```hcl
output "api_execution_arn" {
  description = "HTTP API execution ARN (for Lambda permissions)"
  value       = aws_apigatewayv2_api.rum.execution_arn
}
```

- [ ] **Step 5: Commit API Gateway changes**

```bash
git add terraform/modules/api-gateway/
git commit -m "feat(api-gateway): wire Lambda Authorizer and WAF association to routes"
```

---

## Task 5: Root main.tf — Wire Security Module

**Files:**
- Modify: `terraform/main.tf`
- Modify: `terraform/outputs.tf`

- [ ] **Step 1: Add security module to main.tf**

Add before the `api_gateway` module block in `terraform/main.tf`:

```hcl
# -----------------------------------------------------------------------------
# Security — WAF + Lambda Authorizer
# -----------------------------------------------------------------------------

module "security" {
  source            = "./modules/security"
  project_name      = var.project_name
  environment       = var.environment
  lambda_source_dir = "${path.module}/../lambda/authorizer"
  tags              = { Component = "security" }
}
```

- [ ] **Step 2: Pass security outputs to api_gateway module**

Update the existing `api_gateway` module block in `terraform/main.tf` to add these variables:

```hcl
module "api_gateway" {
  source               = "./modules/api-gateway"
  project_name         = var.project_name
  firehose_stream_name = module.firehose.delivery_stream_name
  firehose_stream_arn  = module.firehose.delivery_stream_arn
  lambda_source_dir    = "${path.module}/../lambda/ingest"
  allowed_origins      = var.allowed_origins
  authorizer_invoke_arn    = module.security.authorizer_invoke_arn
  authorizer_function_name = module.security.authorizer_function_name
  waf_acl_arn              = module.security.waf_acl_arn
  tags                     = { Component = "ingestion" }
}
```

- [ ] **Step 3: Add security outputs to root outputs.tf**

Append to `terraform/outputs.tf`:

```hcl
output "waf_acl_arn" {
  description = "WAF WebACL ARN"
  value       = module.security.waf_acl_arn
}

output "api_key_ssm_name" {
  description = "SSM parameter name for API keys"
  value       = module.security.api_key_ssm_name
}
```

- [ ] **Step 4: Run terraform fmt and validate**

Run: `cd terraform && terraform fmt -recursive`
Expected: Files formatted (may show file names if changes needed)

Run: `cd terraform && terraform validate`
Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit root wiring**

```bash
git add terraform/main.tf terraform/outputs.tf
git commit -m "feat(rum): wire security module into root Terraform configuration"
```

---

## Task 6: Update Integration Test Script

**Files:**
- Modify: `scripts/test-ingestion.sh`

- [ ] **Step 1: Update script to accept API key and add auth tests**

Replace the entire contents of `scripts/test-ingestion.sh`:

```bash
#!/usr/bin/env bash
# scripts/test-ingestion.sh
# End-to-end test: sends sample RUM events to the deployed API endpoint.
# Usage: ./test-ingestion.sh <api-endpoint> <api-key>
# Example: ./test-ingestion.sh https://abc123.execute-api.ap-northeast-2.amazonaws.com rum-dev-abc123

set -euo pipefail

API_ENDPOINT="${1:?Usage: $0 <api-endpoint> <api-key>}"
API_KEY="${2:?Usage: $0 <api-endpoint> <api-key>}"
EVENTS_URL="${API_ENDPOINT}/v1/events"

echo "=== RUM Pipeline Integration Test ==="
echo "Endpoint: ${EVENTS_URL}"
echo ""

# Test 1: Reject request without API key
echo "--- Test 1: No API key (expect 403) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${EVENTS_URL}" \
  -H "Content-Type: application/json" \
  -d '[{"session_id":"test","timestamp":0,"platform":"web","event_type":"test","event_name":"test","payload":{}}]')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
echo "Status: ${HTTP_CODE}"
if [ "$HTTP_CODE" = "403" ]; then echo "PASS"; else echo "FAIL (expected 403, got ${HTTP_CODE})"; exit 1; fi
echo ""

# Test 2: Reject request with invalid API key
echo "--- Test 2: Invalid API key (expect 403) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${EVENTS_URL}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: invalid-key-12345" \
  -d '[{"session_id":"test","timestamp":0,"platform":"web","event_type":"test","event_name":"test","payload":{}}]')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
echo "Status: ${HTTP_CODE}"
if [ "$HTTP_CODE" = "403" ]; then echo "PASS"; else echo "FAIL (expected 403, got ${HTTP_CODE})"; exit 1; fi
echo ""

# Test 3: Single performance event with valid key
echo "--- Test 3: Single performance event ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${EVENTS_URL}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d '[{
    "session_id": "test-sess-001",
    "user_id": "test-user-hash",
    "device_id": "test-dev-001",
    "timestamp": '"$(date +%s000)"',
    "platform": "web",
    "app_version": "1.0.0-test",
    "event_type": "performance",
    "event_name": "lcp",
    "payload": {"value": 2500, "rating": "good"},
    "context": {"url": "/test", "device": {"os": "macOS", "browser": "Chrome 120"}}
  }]')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)
echo "Status: ${HTTP_CODE}"
echo "Body: ${BODY}"
if [ "$HTTP_CODE" = "200" ]; then echo "PASS"; else echo "FAIL"; exit 1; fi
echo ""

# Test 4: Batch of mixed events with valid key
echo "--- Test 4: Batch of 3 mixed events ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${EVENTS_URL}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d '[
    {"session_id":"test-sess-002","user_id":"u1","device_id":"d1","timestamp":'"$(date +%s000)"',"platform":"web","app_version":"1.0.0","event_type":"navigation","event_name":"page_view","payload":{"page":"/home"},"context":{"url":"/home"}},
    {"session_id":"test-sess-002","user_id":"u1","device_id":"d1","timestamp":'"$(date +%s000)"',"platform":"web","app_version":"1.0.0","event_type":"action","event_name":"click","payload":{"target":"#buy-btn"},"context":{"url":"/home"}},
    {"session_id":"test-sess-003","user_id":"u2","device_id":"d2","timestamp":'"$(date +%s000)"',"platform":"ios","app_version":"2.0.0","event_type":"error","event_name":"crash","payload":{"message":"NullPointerException"},"context":{"screen_name":"ProductDetail"}}
  ]')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)
echo "Status: ${HTTP_CODE}"
echo "Body: ${BODY}"
if [ "$HTTP_CODE" = "200" ]; then echo "PASS"; else echo "FAIL"; exit 1; fi
echo ""

# Test 5: Invalid JSON with valid key
echo "--- Test 5: Invalid JSON (expect 400) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${EVENTS_URL}" \
  -H "Content-Type: application/json" \
  -H "x-api-key: ${API_KEY}" \
  -d 'not-valid-json{')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
echo "Status: ${HTTP_CODE}"
if [ "$HTTP_CODE" = "400" ]; then echo "PASS"; else echo "FAIL"; exit 1; fi
echo ""

echo "=== All tests passed ==="
echo ""
echo "Next: Wait ~2 minutes for Firehose buffer to flush, then check S3:"
echo "  aws s3 ls s3://<bucket-name>/raw/ --recursive"
```

- [ ] **Step 2: Commit integration test update**

```bash
git add scripts/test-ingestion.sh
git commit -m "test(e2e): update integration test with API key auth and rejection tests"
```

---

## Task 7: Terraform Plan and Deploy

**Files:** None (validation only)

- [ ] **Step 1: Run all unit tests**

Run: `cd lambda/authorizer && python -m pytest test_handler.py -v`
Expected: 8 tests PASS

Run: `cd lambda/ingest && python -m pytest test_handler.py -v`
Expected: 7 tests PASS (regression check)

Run: `cd lambda/transform && python -m pytest test_handler.py -v`
Expected: 7 tests PASS (regression check)

- [ ] **Step 2: Run terraform init (pick up new module)**

Run: `cd terraform && terraform init`
Expected: `Terraform has been successfully initialized!`

- [ ] **Step 3: Run terraform plan**

Run: `cd terraform && terraform plan -out=tfplan`
Expected: Plan shows new resources:
- `module.security.aws_wafv2_web_acl.rum`
- `module.security.aws_lambda_function.authorizer`
- `module.security.aws_iam_role.authorizer_lambda`
- `module.security.aws_iam_role_policy.authorizer_ssm`
- `module.security.aws_ssm_parameter.api_keys`
- `module.security.random_password.api_key`
- `module.security.aws_cloudwatch_log_group.authorizer_lambda`
- `module.api_gateway.aws_apigatewayv2_authorizer.api_key[0]`
- `module.api_gateway.aws_wafv2_web_acl_association.api[0]`
- `module.api_gateway.aws_lambda_permission.authorizer_apigw[0]`
- Changes to existing routes (add authorization_type)

- [ ] **Step 4: Apply (with user confirmation)**

Run: `cd terraform && terraform apply tfplan`
Expected: Resources created successfully

- [ ] **Step 5: Retrieve API key and run integration tests**

Run: `cd terraform && terraform output -raw api_key_ssm_name`
Expected: `/rum-pipeline/dev/api-keys`

Run: `aws ssm get-parameter --name /rum-pipeline/dev/api-keys --with-decryption --query Parameter.Value --output text`
Expected: A 32-character API key string

Run: `./scripts/test-ingestion.sh $(cd terraform && terraform output -raw api_endpoint) <api-key-from-above>`
Expected: All 5 tests PASS

- [ ] **Step 6: Commit any formatting changes and tag**

```bash
git add -A
git commit -m "feat(rum): deploy Phase 1a.5 security (Lambda Authorizer + WAF)"
```
