<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Partition Repair Lambda

### Role
Athena에서 `MSCK REPAIR TABLE`을 실행하여 Glue 카탈로그에 새 S3 파티션을 자동 등록하는 스케줄 Lambda.

### Key Files
| 파일 | 역할 |
|------|------|
| `handler.py` | Athena MSCK REPAIR TABLE 실행 및 완료 대기 (최대 60초 폴링) |
| `test_handler.py` | pytest 테스트 (성공/실패/취소/폴링 검증) |

### Environment Variables
| 변수 | 용도 |
|------|------|
| `GLUE_DATABASE` | 대상 Glue 데이터베이스 이름 |
| `GLUE_TABLE` | 대상 Glue 테이블 이름 |
| `ATHENA_WORKGROUP` | Athena 쿼리 실행 워크그룹 |

### Key Commands
```bash
cd lambda/partition-repair && python3 -m pytest test_handler.py -v
```

### Rules
- EventBridge 스케줄로 주기적 트리거 (예: 매시간)
- Athena `start_query_execution` 후 5초 간격으로 최대 12회 폴링 (총 60초)
- 쿼리 상태가 `SUCCEEDED`가 아니면 예외 발생 (`FAILED`, `CANCELLED` 포함)
- 쿼리 실패 시 `StateChangeReason`을 로그에 기록 후 Exception raise
- IAM: `athena:StartQueryExecution`, `athena:GetQueryExecution` 권한 필요
- Athena 워크그룹에 결과 출력 위치(S3)가 사전 설정되어 있어야 함
- boto3 mock 기반 pytest 테스트 5개 포함

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Partition Repair Lambda

### Role
Scheduled Lambda that runs `MSCK REPAIR TABLE` via Athena to auto-register new S3 partitions in the Glue catalog.

### Key Files
| File | Role |
|------|------|
| `handler.py` | Executes Athena MSCK REPAIR TABLE and polls for completion (max 60s) |
| `test_handler.py` | pytest tests (success/failure/cancel/polling verification) |

### Environment Variables
| Variable | Purpose |
|----------|---------|
| `GLUE_DATABASE` | Target Glue database name |
| `GLUE_TABLE` | Target Glue table name |
| `ATHENA_WORKGROUP` | Athena query execution workgroup |

### Key Commands
```bash
cd lambda/partition-repair && python3 -m pytest test_handler.py -v
```

### Rules
- Triggered periodically by EventBridge schedule (e.g., hourly)
- Polls Athena every 5 seconds, up to 12 times after `start_query_execution` (60s total)
- Raises exception if query state is not `SUCCEEDED` (includes `FAILED`, `CANCELLED`)
- Logs `StateChangeReason` on failure before raising Exception
- IAM: requires `athena:StartQueryExecution`, `athena:GetQueryExecution` permissions
- Athena workgroup must have an output location (S3) pre-configured
- Includes 5 boto3-mocked pytest tests

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
