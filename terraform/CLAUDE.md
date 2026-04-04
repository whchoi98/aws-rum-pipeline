<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Terraform Module

### Role
RUM Pipeline 전체 AWS 인프라를 Terraform으로 관리.
루트 모듈이 11개 서브모듈을 orchestrate하며 의존성 체인을 형성.

### Key Files
- `main.tf` — 루트 모듈. 모든 서브모듈 호출 및 의존성 연결
- `variables.tf` — 전역 변수 (environment, region, project_name 등)
- `outputs.tf` — 주요 리소스 ARN/URL 출력
- `providers.tf` — AWS provider 설정 (ap-northeast-2 + us-east-1 for Lambda@Edge)
- `backend.tf` — S3 원격 상태 저장소
- `modules/` — 11개 서브모듈

### Module Dependency Chain
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
        └─→ auth (Cognito + Lambda@Edge, us-east-1)
```

### Rules
- `terraform fmt -recursive` 커밋 전 필수
- `terraform validate` CI에서 실행
- 모든 리소스에 `project`, `environment`, `managed_by = "terraform"` 태그
- 시크릿은 SSM Parameter Store 또는 Secrets Manager 참조
- 모듈 간 데이터는 outputs → variable 방식으로만 전달
- `tfplan` 파일은 `.gitignore`에 포함 (이미 존재)

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Terraform Module

### Role
Manages the entire RUM Pipeline AWS infrastructure with Terraform.
The root module orchestrates 11 submodules, forming a dependency chain.

### Key Files
- `main.tf` — Root module. Calls all submodules and wires dependencies
- `variables.tf` — Global variables (environment, region, project_name, etc.)
- `outputs.tf` — Outputs key resource ARNs/URLs
- `providers.tf` — AWS provider configuration (ap-northeast-2 + us-east-1 for Lambda@Edge)
- `backend.tf` — S3 remote state backend
- `modules/` — 11 submodules

### Module Dependency Chain
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
        └─→ auth (Cognito + Lambda@Edge, us-east-1)
```

### Rules
- `terraform fmt -recursive` required before committing
- `terraform validate` runs in CI
- All resources must have `project`, `environment`, `managed_by = "terraform"` tags
- Secrets must reference SSM Parameter Store or Secrets Manager
- Inter-module data must be passed via outputs → variable pattern only
- `tfplan` files are included in `.gitignore` (already present)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
