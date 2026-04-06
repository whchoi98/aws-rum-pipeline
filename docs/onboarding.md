<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 개발자 온보딩 가이드

### 사전 요구사항

| 도구 | 버전 | 용도 |
|------|------|------|
| AWS CLI | v2+ | AWS 리소스 관리 |
| Terraform | 1.5+ | 인프라 프로비저닝 |
| Node.js | 18+ | SDK, CDK, Simulator |
| Python | 3.12+ | Lambda 함수, AgentCore |
| Git | 2.30+ | 버전 관리 |
| Swift | 5.9+ | iOS SDK (선택) |
| Kotlin/Gradle | 1.9+ | Android SDK (선택) |
| Docker | 24+ | Simulator, AgentCore UI (선택) |

### 빠른 시작

```bash
# 1. 저장소 클론
git clone <repo-url> && cd aws-rum-pipeline

# 2. AWS 자격 증명 설정
aws configure --profile default
# 리전: ap-northeast-2 (서울)

# 3. 환경 변수 설정
cp .env.example .env
# .env 파일을 실제 값으로 수정

# 4. 전체 설치 (모든 모듈)
./scripts/setup.sh all

# 또는 필요한 모듈만 설치:
./scripts/setup.sh infra       # Terraform 인프라만
./scripts/setup.sh sdk         # SDK 빌드만
./scripts/setup.sh simulator   # 시뮬레이터만
```

### 작업 영역별 가이드

#### Terraform (인프라)
```bash
cd terraform
terraform init
terraform plan          # 변경사항 확인
terraform fmt -recursive  # 코드 포맷팅 (필수)
```
- 11개 서브모듈 (`modules/` 하위)
- `dev`/`prod` workspace 또는 tfvars로 환경 분리

#### Lambda (백엔드)
```bash
cd lambda/<function-name>
pip install -r requirements.txt  # 의존성 설치
python3 -m pytest test_handler.py -v  # 테스트
```
- 각 함수: authorizer, ingest, transform, partition-repair, athena-query
- Python 3.12, Black 포맷터, type hints 권장

#### SDK (브라우저 클라이언트)
```bash
cd sdk
npm install
npm test        # vitest 실행
npm run build   # esbuild 빌드
```

#### CDK (대체 IaC)
```bash
cd cdk
npm install
npx cdk synth   # CloudFormation 생성
```
- Terraform과 동일 인프라 (ADR-001 참고)

### 프로젝트 구조 이해

핵심 문서를 순서대로 읽으세요:
1. **`CLAUDE.md`** — 프로젝트 전체 구조, 컨벤션, 명령어
2. **`docs/architecture.md`** — 시스템 아키텍처, 데이터 흐름
3. **`docs/decisions/`** — 아키텍처 결정 기록 (ADR)
4. **각 모듈의 `CLAUDE.md`** — 모듈별 역할과 규칙

### 테스트

```bash
# 전체 테스트
./scripts/setup.sh test

# 통합 테스트 (배포 후)
bash scripts/test-ingestion.sh "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com"
```

### 컨벤션

- 주석은 한국어 우선
- 시크릿은 AWS SSM Parameter Store 사용 (하드코딩 금지)
- 리전: `ap-northeast-2` (서울) 기본
- 각 패키지는 독립적 (node_modules, requirements.txt 분리)

---

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Developer Onboarding Guide

### Prerequisites

| Tool | Version | Purpose |
|------|---------|---------|
| AWS CLI | v2+ | AWS resource management |
| Terraform | 1.5+ | Infrastructure provisioning |
| Node.js | 18+ | SDK, CDK, Simulator |
| Python | 3.12+ | Lambda functions, AgentCore |
| Git | 2.30+ | Version control |
| Swift | 5.9+ | iOS SDK (optional) |
| Kotlin/Gradle | 1.9+ | Android SDK (optional) |
| Docker | 24+ | Simulator, AgentCore UI (optional) |

### Quick Start

```bash
# 1. Clone repository
git clone <repo-url> && cd aws-rum-pipeline

# 2. Configure AWS credentials
aws configure --profile default
# Region: ap-northeast-2 (Seoul)

# 3. Set up environment variables
cp .env.example .env
# Edit .env with actual values

# 4. Full installation (all modules)
./scripts/setup.sh all

# Or install only what you need:
./scripts/setup.sh infra       # Terraform infrastructure only
./scripts/setup.sh sdk         # SDK build only
./scripts/setup.sh simulator   # Simulator only
```

### Area-Specific Guides

#### Terraform (Infrastructure)
```bash
cd terraform
terraform init
terraform plan          # Review changes
terraform fmt -recursive  # Format code (required)
```
- 11 submodules under `modules/`
- Environment separation via `dev`/`prod` workspace or tfvars

#### Lambda (Backend)
```bash
cd lambda/<function-name>
pip install -r requirements.txt  # Install dependencies
python3 -m pytest test_handler.py -v  # Run tests
```
- Functions: authorizer, ingest, transform, partition-repair, athena-query
- Python 3.12, Black formatter, type hints recommended

#### SDK (Browser Client)
```bash
cd sdk
npm install
npm test        # Run vitest
npm run build   # Build with esbuild
```

#### CDK (Alternative IaC)
```bash
cd cdk
npm install
npx cdk synth   # Generate CloudFormation
```
- Same infrastructure as Terraform (see ADR-001)

### Understanding the Project

Read these key documents in order:
1. **`CLAUDE.md`** — Project structure, conventions, commands
2. **`docs/architecture.md`** — System architecture, data flow
3. **`docs/decisions/`** — Architecture Decision Records (ADRs)
4. **Each module's `CLAUDE.md`** — Module-specific roles and rules

### Testing

```bash
# Full test suite
./scripts/setup.sh test

# Integration test (after deployment)
bash scripts/test-ingestion.sh "https://<api-id>.execute-api.ap-northeast-2.amazonaws.com"
```

### Conventions

- Korean comments preferred
- Secrets via AWS SSM Parameter Store (no hardcoding)
- Region: `ap-northeast-2` (Seoul) default
- Each package is independent (separate node_modules, requirements.txt)

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
