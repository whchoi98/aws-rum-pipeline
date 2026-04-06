<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Ingest Lambda

### Role
HTTP API Gateway에서 수신한 RUM 이벤트 배치를 Kinesis Data Firehose로 전달하는 브리지 Lambda.

### Key Files
| 파일 | 역할 |
|------|------|
| `handler.py` | HTTP body 파싱, base64 디코딩, Firehose put_record_batch 호출 |
| `test_handler.py` | pytest 테스트 (배치/단건/base64/청크분할/부분실패/에러) |

### Environment Variables
| 변수 | 용도 |
|------|------|
| `FIREHOSE_STREAM_NAME` | 대상 Kinesis Data Firehose Delivery Stream 이름 |

### Key Commands
```bash
cd lambda/ingest && python3 -m pytest test_handler.py -v
```

### Rules
- 단일 이벤트(dict)와 배치 이벤트(list) 모두 지원 -- 단일 이벤트는 자동으로 리스트 래핑
- `isBase64Encoded: true`인 경우 body를 base64 디코딩 후 처리
- Firehose `put_record_batch` 제한: 호출당 최대 500건 -- 초과 시 자동 청크 분할
- 각 레코드는 JSON 직렬화 후 개행 문자(`\n`) 추가하여 전송
- 부분 실패 시 HTTP 207 (FailedPutCount > 0), 완전 성공 시 HTTP 200
- 빈 리스트 또는 잘못된 JSON은 HTTP 400 반환
- CORS: `Access-Control-Allow-Origin: *` 헤더 포함
- IAM: `firehose:PutRecordBatch` 권한 필요

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Ingest Lambda

### Role
Bridge Lambda that forwards RUM event batches received from HTTP API Gateway to Kinesis Data Firehose.

### Key Files
| File | Role |
|------|------|
| `handler.py` | Parses HTTP body, decodes base64, calls Firehose put_record_batch |
| `test_handler.py` | pytest tests (batch/single/base64/chunking/partial failure/error) |

### Environment Variables
| Variable | Purpose |
|----------|---------|
| `FIREHOSE_STREAM_NAME` | Target Kinesis Data Firehose Delivery Stream name |

### Key Commands
```bash
cd lambda/ingest && python3 -m pytest test_handler.py -v
```

### Rules
- Accepts both single events (dict) and batch events (list) -- single events are auto-wrapped in a list
- Decodes base64 body when `isBase64Encoded: true`
- Firehose `put_record_batch` limit: max 500 records per call -- auto-chunks when exceeded
- Each record is JSON-serialized with a trailing newline (`\n`)
- Partial failure returns HTTP 207 (FailedPutCount > 0), full success returns HTTP 200
- Empty list or invalid JSON returns HTTP 400
- CORS: includes `Access-Control-Allow-Origin: *` header
- IAM: requires `firehose:PutRecordBatch` permission

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
