<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## Scripts Module

### Role
빌드, 배포, 프로비저닝, 테스트를 위한 쉘 스크립트 모음.

### Key Files
| 스크립트 | 역할 |
|----------|------|
| `setup.sh` | 전체 프로젝트 설치 (`./setup.sh all`) |
| `test-ingestion.sh` | 엔드투엔드 인제스천 파이프라인 테스트 |
| `provision-grafana.sh` | Grafana 워크스페이스 데이터소스/대시보드 프로비저닝 |
| `setup-agentcore.sh` | AgentCore 환경 설정 (scripts/ 에 위치) |
| `deploy-unified-dashboard.py` | 통합 Grafana 대시보드 배포 (scripts/ 에 위치) |

### Key Commands
```bash
./scripts/setup.sh all                                    # 전체 설치
bash scripts/test-ingestion.sh "<api-endpoint>"           # 인제스천 테스트
bash scripts/provision-grafana.sh                         # Grafana 프로비저닝
```

### Rules
- 모든 스크립트에 `chmod +x` 적용 필요
- 스크립트 상단에 `set -euo pipefail` 권장
- AWS 리전은 `ap-northeast-2` 기본
- 시크릿은 AWS SSM에서 동적으로 읽어옴 (스크립트 내 하드코딩 금지)
- `bash -n <script>` 로 문법 검증 가능

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Scripts Module

### Role
A collection of shell scripts for building, deploying, provisioning, and testing.

### Key Files
| Script | Role |
|--------|------|
| `setup.sh` | Full project installation (`./setup.sh all`) |
| `test-ingestion.sh` | End-to-end ingestion pipeline test |
| `provision-grafana.sh` | Grafana workspace datasource/dashboard provisioning |
| `setup-agentcore.sh` | AgentCore environment setup (located in scripts/) |
| `deploy-unified-dashboard.py` | Unified Grafana dashboard deployment (located in scripts/) |

### Key Commands
```bash
./scripts/setup.sh all                                    # Full installation
bash scripts/test-ingestion.sh "<api-endpoint>"           # Ingestion test
bash scripts/provision-grafana.sh                         # Grafana provisioning
```

### Rules
- All scripts require `chmod +x`
- `set -euo pipefail` recommended at the top of each script
- Default AWS region is `ap-northeast-2`
- Secrets are read dynamically from AWS SSM (no hardcoding in scripts)
- Syntax can be validated with `bash -n <script>`

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
