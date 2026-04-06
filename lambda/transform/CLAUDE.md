<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Transform Lambda

### Role
Firehose 데이터 변환 Lambda -- 스키마 검증, PII 제거, 파티션 키 추출, Parquet 호환 직렬화 수행.

### Key Files
| 파일 | 역할 |
|------|------|
| `handler.py` | Firehose 레코드 변환 (스키마 검증, IP 제거, 파티션 키 생성) |
| `test_handler.py` | pytest 테스트 (스키마/파티션키/PII제거/배치처리 시나리오) |

### Environment Variables
| 변수 | 용도 |
|------|------|
| (없음) | 환경변수 없이 동작 -- 모든 설정은 코드 내 상수 |

### Key Commands
```bash
cd lambda/transform && python3 -m pytest test_handler.py -v
```

### Rules
- 필수 필드: `session_id`, `timestamp`, `platform`, `event_type`, `event_name` -- 누락 시 `ProcessingFailed`
- PII 제거: 루트 및 `context` 내 `ip` 필드 자동 삭제
- 타임스탬프 처리: epoch 밀리초(int/float) 및 ISO 8601 문자열 모두 지원
- 파티션 키: `platform`, `year`, `month`, `day`, `hour` (UTC 기준)
- `payload`와 `context` 필드가 dict인 경우 JSON 문자열로 직렬화 (Parquet 호환)
- 각 레코드는 독립적으로 처리 -- 한 레코드 실패가 다른 레코드에 영향 없음
- JSON 파싱 오류, 키 누락, 타입 오류 모두 `ProcessingFailed`로 처리
- Firehose 변환 응답 형식: `recordId`, `result` ("Ok" | "ProcessingFailed"), `data`, `metadata`

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Transform Lambda

### Role
Firehose data transformation Lambda -- performs schema validation, PII stripping, partition key extraction, and Parquet-compatible serialization.

### Key Files
| File | Role |
|------|------|
| `handler.py` | Transforms Firehose records (schema validation, IP removal, partition key generation) |
| `test_handler.py` | pytest tests (schema/partition keys/PII stripping/batch processing scenarios) |

### Environment Variables
| Variable | Purpose |
|----------|---------|
| (none) | No environment variables -- all configuration is via in-code constants |

### Key Commands
```bash
cd lambda/transform && python3 -m pytest test_handler.py -v
```

### Rules
- Required fields: `session_id`, `timestamp`, `platform`, `event_type`, `event_name` -- missing fields yield `ProcessingFailed`
- PII stripping: automatically removes `ip` field from root and `context`
- Timestamp handling: supports both epoch milliseconds (int/float) and ISO 8601 strings
- Partition keys: `platform`, `year`, `month`, `day`, `hour` (UTC-based)
- `payload` and `context` fields are serialized to JSON strings if they are dicts (Parquet compatibility)
- Each record is processed independently -- one record failure does not affect others
- JSON parse errors, missing keys, and type errors all result in `ProcessingFailed`
- Firehose transform response format: `recordId`, `result` ("Ok" | "ProcessingFailed"), `data`, `metadata`

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
