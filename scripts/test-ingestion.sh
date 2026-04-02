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
