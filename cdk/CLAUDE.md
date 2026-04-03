# CDK Module

## Role
Terraform과 동일한 RUM Pipeline 인프라를 AWS CDK (TypeScript)로 관리.
10개 Construct가 Terraform 10개 모듈과 1:1 대응.

## Key Files
| 파일 | 역할 | Terraform 대응 |
|------|------|---------------|
| `bin/app.ts` | CDK 앱 엔트리포인트 | `main.tf` (root) |
| `lib/rum-pipeline-stack.ts` | 메인 스택 — 모든 Construct 조합 | `main.tf` |
| `lib/constructs/s3-data-lake.ts` | S3 버킷 + 생명주기 | `modules/s3-data-lake/` |
| `lib/constructs/glue-catalog.ts` | Glue DB + 3개 테이블 | `modules/glue-catalog/` |
| `lib/constructs/firehose.ts` | Firehose + Transform Lambda | `modules/firehose/` |
| `lib/constructs/security.ts` | WAF + SSM + Authorizer | `modules/security/` |
| `lib/constructs/api-gateway.ts` | HTTP API + Ingest Lambda | `modules/api-gateway/` |
| `lib/constructs/grafana.ts` | Managed Grafana + Athena WG | `modules/grafana/` |
| `lib/constructs/monitoring.ts` | CloudWatch Dashboard | `modules/monitoring/` |
| `lib/constructs/partition-repair.ts` | 파티션 복구 Lambda + EventBridge | `modules/partition-repair/` |
| `lib/constructs/athena-query.ts` | Athena Query Lambda | `modules/athena-query/` |
| `lib/constructs/agent-ui.ts` | CloudFront + ALB + EC2 | `modules/agent-ui/` |

## Key Commands
```bash
cd cdk && npm install
cd cdk && npx cdk synth          # CloudFormation 템플릿 생성
cd cdk && npx cdk diff           # 변경사항 확인
cd cdk && npx cdk deploy         # 배포
cd cdk && npx cdk destroy        # 삭제
```

## Context 변수
```bash
npx cdk deploy \
  -c vpcId=vpc-xxx \
  -c publicSubnetIds='["subnet-aaa","subnet-bbb"]' \
  -c agentcoreEndpointArn='arn:aws:bedrock-agentcore:...'
```

## Rules
- Lambda 소스는 `../lambda/` 디렉터리를 그대로 참조
- Terraform과 동일한 리소스 이름 컨벤션 유지 (`{projectName}-{component}`)
- 보안 민감 값은 context 또는 환경변수로 전달 (하드코딩 금지)
- `cdk.json`의 context에서 기본값 설정 가능
