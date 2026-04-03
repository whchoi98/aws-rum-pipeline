# Terraform Module

## Role
RUM Pipeline 전체 AWS 인프라를 Terraform으로 관리.
루트 모듈이 8개 서브모듈을 orchestrate하며 의존성 체인을 형성.

## Key Files
- `main.tf` — 루트 모듈. 모든 서브모듈 호출 및 의존성 연결
- `variables.tf` — 전역 변수 (environment, region, project_name 등)
- `outputs.tf` — 주요 리소스 ARN/URL 출력
- `providers.tf` — AWS provider 설정 (ap-northeast-2)
- `backend.tf` — S3 원격 상태 저장소
- `modules/` — 8개 서브모듈

## Module Dependency Chain
```
s3-data-lake
  └─→ glue-catalog
  └─→ firehose
        └─→ api-gateway
              └─→ security
                    └─→ monitoring
                    └─→ grafana
  └─→ partition-repair
  └─→ athena-query
  └─→ agent-ui
```

## Rules
- `terraform fmt -recursive` 커밋 전 필수
- `terraform validate` CI에서 실행
- 모든 리소스에 `project`, `environment`, `managed_by = "terraform"` 태그
- 시크릿은 SSM Parameter Store 또는 Secrets Manager 참조
- 모듈 간 데이터는 outputs → variable 방식으로만 전달
- `tfplan` 파일은 `.gitignore`에 포함 (이미 존재)
