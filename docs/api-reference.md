<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## API 레퍼런스

### 개요

RUM Pipeline은 HTTP API Gateway를 통해 2개의 공개 엔드포인트를 제공합니다.
Athena 쿼리 Lambda는 API Gateway에 노출되지 않고 직접 호출(AgentCore 등)로만 사용됩니다.

### 기본 URL

```
https://<api-id>.execute-api.ap-northeast-2.amazonaws.com
```

---

### POST `/v1/events`

RUM 이벤트를 Firehose로 전송합니다.

**요청**

```http
POST /v1/events HTTP/1.1
Content-Type: application/json
x-api-key: <api-key>          # 인증 활성화 시 필수
```

```json
[
  { "event_type": "page_view", "url": "https://example.com", "timestamp": 1700000000 },
  { "event_type": "click", "element": "#btn", "timestamp": 1700000001 }
]
```

- 단일 JSON 객체 또는 JSON 배열 지원
- Base64 인코딩된 body 자동 감지

**응답**

| 상태 코드 | 조건 | Body |
|-----------|------|------|
| 200 | 전체 성공 | `{"status": "ok", "count": 2}` |
| 207 | 부분 실패 | `{"status": "partial", "count": 1, "failed": 1}` |
| 400 | 유효하지 않은 JSON | `{"error": "Invalid JSON"}` |
| 400 | 빈 이벤트 목록 | `{"error": "Empty event list"}` |

---

### POST `/v1/events/beacon`

`/v1/events`와 동일. 브라우저 `navigator.sendBeacon()` 호출용 별도 경로.

---

### 인증 (선택적)

Lambda Authorizer 기반 API Key 검증.

| 항목 | 값 |
|------|-----|
| 헤더 | `x-api-key` |
| 검증 방식 | SSM Parameter Store에서 유효 키 목록 조회 |
| 캐시 TTL | 300초 (5분) |
| 활성화 | `enable_auth = true` (Terraform 변수) |

---

### CORS 설정

| 항목 | 값 |
|------|-----|
| Allowed Origins | `*` (설정 가능: `allowed_origins` 변수) |
| Allowed Methods | `POST`, `OPTIONS` |
| Allowed Headers | `Content-Type`, `x-api-key`, `x-rum-session` |
| Max Age | 86400초 (24시간) |

---

### 속도 제한

| 계층 | 제한 |
|------|------|
| API Gateway Stage | Burst 1,000 / 평균 500 req/sec |
| WAF (선택) | IP당 2,000 req (설정 가능) |

---

### Athena 쿼리 Lambda (직접 호출 전용)

API Gateway에 노출되지 않음. `lambda:InvokeFunction`으로 직접 호출.

**입력 이벤트**

```json
{
  "name": "tool_name",
  "input": {
    "sql": "SELECT * FROM rum_events LIMIT 10"
  }
}
```

- `SELECT`, `SHOW`, `DESCRIBE` 쿼리만 허용

**응답**

```json
{
  "data": [{"column1": "value1"}],
  "rowCount": 1,
  "columns": ["column1"],
  "queryId": "execution-id"
}
```

- 최대 대기 시간: 30초 (15회 × 2초 폴링)

---

### 관련 파일

| 파일 | 역할 |
|------|------|
| `terraform/modules/api-gateway/main.tf` | API Gateway 인프라 정의 |
| `cdk/lib/constructs/api-gateway.ts` | CDK API Gateway Construct |
| `lambda/ingest/handler.py` | 이벤트 수집 핸들러 |
| `lambda/authorizer/handler.py` | API Key 검증 핸들러 |
| `lambda/athena-query/handler.py` | Athena 쿼리 핸들러 |

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## API Reference

### Overview

RUM Pipeline exposes 2 public endpoints via HTTP API Gateway.
The Athena query Lambda is not exposed via API Gateway — it is invoked directly (e.g., by AgentCore).

### Base URL

```
https://<api-id>.execute-api.ap-northeast-2.amazonaws.com
```

---

### POST `/v1/events`

Send RUM events to Firehose.

**Request**

```http
POST /v1/events HTTP/1.1
Content-Type: application/json
x-api-key: <api-key>          # Required when auth is enabled
```

```json
[
  { "event_type": "page_view", "url": "https://example.com", "timestamp": 1700000000 },
  { "event_type": "click", "element": "#btn", "timestamp": 1700000001 }
]
```

- Accepts single JSON object or JSON array
- Auto-detects Base64-encoded body

**Response**

| Status Code | Condition | Body |
|-------------|-----------|------|
| 200 | All records sent | `{"status": "ok", "count": 2}` |
| 207 | Partial failure | `{"status": "partial", "count": 1, "failed": 1}` |
| 400 | Invalid JSON | `{"error": "Invalid JSON"}` |
| 400 | Empty event list | `{"error": "Empty event list"}` |

---

### POST `/v1/events/beacon`

Identical to `/v1/events`. Separate route for browser `navigator.sendBeacon()` calls.

---

### Authentication (Optional)

Lambda Authorizer-based API Key validation.

| Item | Value |
|------|-------|
| Header | `x-api-key` |
| Validation | Fetches valid keys from SSM Parameter Store |
| Cache TTL | 300 seconds (5 minutes) |
| Enable | `enable_auth = true` (Terraform variable) |

---

### CORS Configuration

| Item | Value |
|------|-------|
| Allowed Origins | `*` (configurable via `allowed_origins` variable) |
| Allowed Methods | `POST`, `OPTIONS` |
| Allowed Headers | `Content-Type`, `x-api-key`, `x-rum-session` |
| Max Age | 86400 seconds (24 hours) |

---

### Rate Limiting

| Layer | Limit |
|-------|-------|
| API Gateway Stage | Burst 1,000 / Average 500 req/sec |
| WAF (optional) | 2,000 req per IP (configurable) |

---

### Athena Query Lambda (Direct Invocation Only)

Not exposed via API Gateway. Invoked directly via `lambda:InvokeFunction`.

**Input Event**

```json
{
  "name": "tool_name",
  "input": {
    "sql": "SELECT * FROM rum_events LIMIT 10"
  }
}
```

- Only `SELECT`, `SHOW`, `DESCRIBE` queries allowed

**Response**

```json
{
  "data": [{"column1": "value1"}],
  "rowCount": 1,
  "columns": ["column1"],
  "queryId": "execution-id"
}
```

- Max wait time: 30 seconds (15 iterations × 2-second polling)

---

### Related Files

| File | Role |
|------|------|
| `terraform/modules/api-gateway/main.tf` | API Gateway infrastructure |
| `cdk/lib/constructs/api-gateway.ts` | CDK API Gateway Construct |
| `lambda/ingest/handler.py` | Event ingestion handler |
| `lambda/authorizer/handler.py` | API Key validation handler |
| `lambda/athena-query/handler.py` | Athena query handler |

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
