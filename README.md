# AWS Custom RUM Pipeline

Datadog RUM을 대체하는 AWS 서버리스 기반 Real User Monitoring 파이프라인.

## 아키텍처

```
SDK (Web/iOS/Android)
    | HTTPS + x-api-key
    v
WAF WebACL (Rate Limit + Bot Control)
    |
    v
HTTP API Gateway → Lambda Authorizer (SSM API Key 검증)
    |
    v
Ingest Lambda → Kinesis Firehose → Transform Lambda → S3 Data Lake (Parquet)
    |                                                        |
    v                                                        v
CloudWatch Dashboard (22 위젯)                    Athena → Managed Grafana
                                                            |
EventBridge (15분) → Partition Repair Lambda ─────────────────┘
                                                            |
EKS CronJob (5분) → Simulator (테스트 트래픽) ────────────────┘
```

## 빠른 시작

```bash
# 전체 설치
./scripts/setup.sh all

# 단계별 설치
./scripts/setup.sh infra       # 1. Terraform 인프라
./scripts/setup.sh sdk         # 2. SDK 빌드
./scripts/setup.sh simulator   # 3. 시뮬레이터 테스트
./scripts/setup.sh grafana     # 4. Grafana 대시보드
./scripts/setup.sh eks         # 5. EKS CronJob
./scripts/setup.sh test        # 전체 테스트
```

## 사전 조건

- AWS CLI v2 + 자격증명
- Terraform >= 1.5
- Node.js >= 18
- Python >= 3.9
- kubectl (EKS 배포 시)

## 프로젝트 구조

```
rum/
├── terraform/                    # IaC (Terraform)
│   ├── main.tf                   # 루트 모듈 (8개 모듈 연결)
│   └── modules/
│       ├── s3-data-lake/         # S3 데이터 레이크 + 라이프사이클
│       ├── glue-catalog/         # Glue Data Catalog (rum_events 등)
│       ├── firehose/             # Kinesis Firehose + Transform Lambda
│       ├── api-gateway/          # HTTP API + Ingest Lambda + Authorizer
│       ├── security/             # WAF WebACL + API Key (SSM)
│       ├── monitoring/           # CloudWatch Dashboard (22 위젯)
│       ├── grafana/              # Managed Grafana + Athena Workgroup
│       └── partition-repair/     # Glue 파티션 자동 등록 (EventBridge)
├── lambda/                       # Lambda 함수 (Python)
│   ├── authorizer/               # API Key 검증
│   ├── ingest/                   # HTTP → Firehose 포워딩
│   ├── transform/                # 스키마 검증 + PII 제거 + 파티셔닝
│   └── partition-repair/         # MSCK REPAIR TABLE 실행
├── sdk/                          # Web RUM SDK (TypeScript)
│   ├── src/                      # 소스 (buffer, transport, collectors)
│   └── tests/                    # 단위 테스트 (vitest)
├── simulator/                    # 트래픽 시뮬레이터 (TypeScript)
│   ├── src/                      # 이벤트 생성기 (Web/iOS/Android)
│   └── k8s/                      # EKS CronJob YAML
├── scripts/                      # 운영 스크립트
│   ├── setup.sh                  # 통합 설치 스크립트
│   ├── test-ingestion.sh         # E2E 통합 테스트
│   ├── deploy-unified-dashboard.py  # Grafana 대시보드 배포
│   └── provision-grafana.sh      # Grafana 데이터소스 프로비저닝
└── docs/                         # 설계 문서
    └── superpowers/
        ├── specs/                # 설계 스펙 (4개)
        └── plans/                # 구현 계획 (4개)
```

## 배포된 리소스

| 리소스 | 값 |
|--------|-----|
| API Endpoint | https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com |
| Grafana | https://g-c8cc9b0a52.grafana-workspace.ap-northeast-2.amazonaws.com |
| SSO Portal | https://d-9b6773f833.awsapps.com/start |
| S3 Data Lake | rum-pipeline-data-lake-061525506239 |
| Glue Database | rum_pipeline_db |
| Athena Workgroup | rum-pipeline-athena |
| CloudWatch Dashboard | rum-pipeline-dashboard |
| Region | ap-northeast-2 |

## 테스트

```bash
# Lambda 단위 테스트
cd lambda/authorizer && python3 -m pytest test_handler.py -v
cd lambda/ingest && python3 -m pytest test_handler.py -v
cd lambda/transform && python3 -m pytest test_handler.py -v

# SDK 단위 테스트
cd sdk && npx vitest run

# 시뮬레이터 테스트
cd simulator && npx vitest run

# E2E 통합 테스트
API_KEY=$(aws ssm get-parameter --name /rum-pipeline/dev/api-keys \
  --with-decryption --query Parameter.Value --output text --region ap-northeast-2)
./scripts/test-ingestion.sh https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com "$API_KEY"
```

## SDK 사용법

```typescript
import { RumSDK } from '@myorg/rum-sdk';

RumSDK.init({
  endpoint: 'https://ucsstumep1.execute-api.ap-northeast-2.amazonaws.com',
  apiKey: 'your-api-key',
  appVersion: '1.0.0',
});
```

## 비용 추정 (DAU 5만 기준)

| 서비스 | 월 비용 |
|--------|---------|
| API Gateway (HTTP API) | ~$15 |
| Kinesis Firehose | ~$30 |
| Lambda (4개 함수) | ~$25 |
| S3 Storage | ~$25 |
| WAF (Rate + Bot Control) | ~$19 |
| Managed Grafana | ~$9 |
| Athena Queries | ~$1 |
| **합계** | **~$124/월** |

Datadog RUM ($1,500~3,000/월) 대비 **~92~96% 절감**
