<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Athena Query Lambda

### Role
Athena SQL 쿼리를 실행하고 결과를 반환하는 Lambda -- AgentCore RUM 분석 에이전트 및 MCP Gateway의 도구로 사용.

### Key Files
| 파일 | 역할 |
|------|------|
| `handler.py` | SQL 안전성 검증, Athena 쿼리 실행, 결과 파싱 및 반환 |

### Environment Variables
| 변수 | 용도 | 기본값 |
|------|------|--------|
| `GLUE_DATABASE` | 대상 Glue 데이터베이스 이름 | `rum_pipeline_db` |
| `ATHENA_WORKGROUP` | Athena 쿼리 실행 워크그룹 | `rum-pipeline-athena` |

### Key Commands
```bash
cd lambda/athena-query && python3 -m pytest test_handler.py -v
```

### Rules
- `SELECT`, `SHOW`, `DESCRIBE`만 허용 -- DDL/DML 차단 (SQL 인젝션 방지)
- MCP Gateway 호출 형식 지원: `event.name`(도구명) + `event.input.sql`(쿼리)
- Athena 폴링: 2초 간격, 최대 15회 (총 30초)
- 결과 형식: `{"data": [...], "rowCount": N, "columns": [...], "queryId": "..."}`
- 오류 시 `{"error": "메시지"}` 반환 (Exception을 raise하지 않음)
- 첫 번째 행을 컬럼 헤더로 사용하여 딕셔너리 리스트로 변환
- IAM: `athena:StartQueryExecution`, `athena:GetQueryExecution`, `athena:GetQueryResults` 권한 필요
- 테스트 파일 없음 -- boto3 mock으로 테스트 추가 권장

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Athena Query Lambda

### Role
Executes Athena SQL queries and returns results -- used as a tool by the AgentCore RUM analytics agent and MCP Gateway.

### Key Files
| File | Role |
|------|------|
| `handler.py` | SQL safety validation, Athena query execution, result parsing and return |

### Environment Variables
| Variable | Purpose | Default |
|----------|---------|---------|
| `GLUE_DATABASE` | Target Glue database name | `rum_pipeline_db` |
| `ATHENA_WORKGROUP` | Athena query execution workgroup | `rum-pipeline-athena` |

### Key Commands
```bash
cd lambda/athena-query && python3 -m pytest test_handler.py -v
```

### Rules
- Only `SELECT`, `SHOW`, `DESCRIBE` are allowed -- DDL/DML is blocked (SQL injection prevention)
- Supports MCP Gateway invocation format: `event.name` (tool name) + `event.input.sql` (query)
- Athena polling: 2-second intervals, max 15 attempts (30s total)
- Result format: `{"data": [...], "rowCount": N, "columns": [...], "queryId": "..."}`
- Errors return `{"error": "message"}` (does not raise exceptions)
- First row is used as column headers, data is converted to a list of dictionaries
- IAM: requires `athena:StartQueryExecution`, `athena:GetQueryExecution`, `athena:GetQueryResults` permissions
- No test file present -- adding boto3-mocked tests is recommended

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
