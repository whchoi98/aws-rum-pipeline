<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Monitoring Module

### Role
CloudWatch 대시보드를 관리하여 RUM 파이프라인 전체(API Gateway, Lambda, WAF, Firehose)를 단일 뷰로 모니터링.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_cloudwatch_dashboard` | 8개 행, 20+ 위젯으로 구성된 운영 대시보드 |

### Dashboard Layout (8 Rows)
| 행 | 내용 |
|----|------|
| Row 0 | 헤더 텍스트 (파이프라인 플로우 설명) |
| Row 1 | API Gateway 주요 지표 (총 요청, 4xx, 5xx, 평균 지연) |
| Row 2 | API Gateway 시계열 (요청 추이, 에러 추이) |
| Row 3 | API 지연 시간 백분위수 (p50/p90/p99) + 데이터 처리량 |
| Row 4 | Lambda 함수별 호출/에러 (Authorizer, Ingest, Transform) |
| Row 5 | Lambda 실행 시간 (평균, p99) |
| Row 6 | Lambda 동시 실행 수 + 스로틀 횟수 |
| Row 7 | WAF 허용/차단, Rate Limit, Bot Control |
| Row 8 | Firehose 수신 레코드, S3 전송, 수신 바이트 |

### Input Variables
| 변수 | 설명 |
|------|------|
| `project_name` | 대시보드명 및 메트릭 차원 값에 사용 |
| `region` | 메트릭 조회 리전 |
| `api_id` | API Gateway HTTP API ID |

### Rules
- 대시보드 위젯은 `project_name`으로 Lambda 함수명, Firehose 스트림명, WAF 이름을 동적으로 참조함 — 네이밍 규칙 변경 시 이 모듈도 수정 필요
- 한국어 라벨 사용 (운영팀 기준)
- 대시보드 JSON은 `jsonencode`로 인라인 생성 — 위젯 추가/제거 시 좌표(x, y)값 주의

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Monitoring Module

### Role
Manages a CloudWatch dashboard to provide a single-pane view of the entire RUM pipeline (API Gateway, Lambda, WAF, Firehose).

### Key Resources
| Resource | Role |
|----------|------|
| `aws_cloudwatch_dashboard` | Operations dashboard with 8 rows, 20+ widgets |

### Dashboard Layout (8 Rows)
| Row | Content |
|-----|---------|
| Row 0 | Header text (pipeline flow description) |
| Row 1 | API Gateway key metrics (total requests, 4xx, 5xx, avg latency) |
| Row 2 | API Gateway time series (request trend, error trend) |
| Row 3 | API latency percentiles (p50/p90/p99) + data throughput |
| Row 4 | Lambda invocations/errors per function (Authorizer, Ingest, Transform) |
| Row 5 | Lambda duration (average, p99) |
| Row 6 | Lambda concurrent executions + throttles |
| Row 7 | WAF allowed/blocked, Rate Limit, Bot Control |
| Row 8 | Firehose incoming records, S3 delivery, incoming bytes |

### Input Variables
| Variable | Description |
|----------|-------------|
| `project_name` | Used for dashboard name and metric dimension values |
| `region` | Region for metric queries |
| `api_id` | API Gateway HTTP API ID |

### Rules
- Dashboard widgets dynamically reference Lambda function names, Firehose stream names, and WAF names via `project_name` — changes to naming conventions require updating this module
- Labels use Korean (for operations team)
- Dashboard JSON is generated inline with `jsonencode` — pay attention to coordinate (x, y) values when adding/removing widgets

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
