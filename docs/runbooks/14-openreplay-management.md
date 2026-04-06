<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: OpenReplay 관리

### 개요
OpenReplay 인스턴스 상태 확인, 버전 업그레이드, 장애 복구 절차.

### 사전 조건
- AWS CLI v2+ 인증 완료 (`aws sts get-caller-identity`)
- SSM Session Manager 플러그인 설치 (`session-manager-plugin`)
- OpenReplay EC2 인스턴스 ID 확인 (`terraform output openreplay_instance_id`)

### 절차

#### 1. 상태 확인

```bash
# SSM 세션으로 EC2 접속
INSTANCE_ID=$(cd terraform && terraform output -raw openreplay_instance_id)
aws ssm start-session --target "${INSTANCE_ID}"

# Docker Compose 상태 확인
cd /opt/openreplay && docker compose ps

# 컨테이너 로그 확인 (최근 100줄)
docker compose logs --tail=100

# 특정 서비스 로그 (예: backend)
docker compose logs --tail=100 backend

# 디스크 사용량 확인 (Kafka 데이터에 주의)
df -h /
du -sh /opt/openreplay/data/*
```

#### 2. 버전 업그레이드

```bash
# SSM 세션으로 EC2 접속
aws ssm start-session --target "${INSTANCE_ID}"

# 현재 버전 확인
cd /opt/openreplay
git describe --tags

# 최신 태그 확인 및 체크아웃
git fetch --tags
git tag -l | sort -V | tail -5
git checkout <target-tag>

# 이미지 업데이트 및 재시작
docker compose pull
docker compose up -d

# 상태 확인
docker compose ps
docker compose logs --tail=50
```

#### 3. EC2 교체 (인스턴스 장애 시)

데이터는 RDS, S3에 저장되므로 EC2 교체 시 데이터 손실 없음.

```bash
# Terraform으로 인스턴스 교체
cd terraform
terraform taint 'module.openreplay[0].aws_instance.openreplay'
terraform plan -out=tfplan
terraform apply tfplan

# 새 인스턴스 확인 (user_data로 자동 설치됨)
INSTANCE_ID=$(terraform output -raw openreplay_instance_id)
aws ssm start-session --target "${INSTANCE_ID}"
cd /opt/openreplay && docker compose ps
```

#### 4. RDS 스냅샷 복원

```bash
# 사용 가능한 스냅샷 목록
aws rds describe-db-snapshots \
  --db-instance-identifier rum-pipeline-openreplay \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# 스냅샷에서 새 인스턴스 복원 (Terraform 외부)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier rum-pipeline-openreplay-restored \
  --db-snapshot-identifier <snapshot-id> \
  --db-instance-class db.t4g.medium

# 복원 후 Terraform state 업데이트 필요 — 주의하여 진행
```

### 모니터링

| 지표 | 경보 조건 | 확인 방법 |
|------|----------|----------|
| EC2 CPU | > 80% 5분 | CloudWatch → EC2 메트릭 |
| EC2 메모리 | > 85% | SSM 접속 → `free -h` |
| Kafka 디스크 | > 70% | SSM 접속 → `du -sh /opt/openreplay/data/kafka` |
| RDS 연결 수 | > 80% max | CloudWatch → RDS 메트릭 → DatabaseConnections |
| RDS 스토리지 | > 80% | CloudWatch → RDS 메트릭 → FreeStorageSpace |
| Redis 메모리 | > 80% eviction | CloudWatch → ElastiCache 메트릭 |

### 롤백
```bash
# OpenReplay 비활성화 (인프라 전체 제거)
# terraform.tfvars에서 enable_openreplay = false 설정 후
cd terraform && terraform plan -out=tfplan && terraform apply tfplan
```

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: OpenReplay Management

### Overview
Procedures for checking OpenReplay instance health, upgrading versions, and recovering from failures.

### Prerequisites
- AWS CLI v2+ authenticated (`aws sts get-caller-identity`)
- SSM Session Manager plugin installed (`session-manager-plugin`)
- OpenReplay EC2 instance ID available (`terraform output openreplay_instance_id`)

### Procedures

#### 1. Health Check

```bash
# Connect to EC2 via SSM session
INSTANCE_ID=$(cd terraform && terraform output -raw openreplay_instance_id)
aws ssm start-session --target "${INSTANCE_ID}"

# Check Docker Compose status
cd /opt/openreplay && docker compose ps

# View container logs (last 100 lines)
docker compose logs --tail=100

# View specific service logs (e.g., backend)
docker compose logs --tail=100 backend

# Check disk usage (watch Kafka data)
df -h /
du -sh /opt/openreplay/data/*
```

#### 2. Version Upgrade

```bash
# Connect to EC2 via SSM session
aws ssm start-session --target "${INSTANCE_ID}"

# Check current version
cd /opt/openreplay
git describe --tags

# Fetch and checkout latest tag
git fetch --tags
git tag -l | sort -V | tail -5
git checkout <target-tag>

# Update images and restart
docker compose pull
docker compose up -d

# Verify status
docker compose ps
docker compose logs --tail=50
```

#### 3. EC2 Replacement (Instance Failure)

Data is stored in RDS and S3, so EC2 replacement causes no data loss.

```bash
# Replace instance via Terraform
cd terraform
terraform taint 'module.openreplay[0].aws_instance.openreplay'
terraform plan -out=tfplan
terraform apply tfplan

# Verify new instance (auto-installed via user_data)
INSTANCE_ID=$(terraform output -raw openreplay_instance_id)
aws ssm start-session --target "${INSTANCE_ID}"
cd /opt/openreplay && docker compose ps
```

#### 4. RDS Snapshot Restore

```bash
# List available snapshots
aws rds describe-db-snapshots \
  --db-instance-identifier rum-pipeline-openreplay \
  --query 'DBSnapshots[*].[DBSnapshotIdentifier,SnapshotCreateTime]' \
  --output table

# Restore new instance from snapshot (outside Terraform)
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier rum-pipeline-openreplay-restored \
  --db-snapshot-identifier <snapshot-id> \
  --db-instance-class db.t4g.medium

# Terraform state update required after restore — proceed with caution
```

### Monitoring

| Metric | Alert Condition | How to Check |
|--------|----------------|--------------|
| EC2 CPU | > 80% for 5 min | CloudWatch → EC2 Metrics |
| EC2 Memory | > 85% | SSM session → `free -h` |
| Kafka Disk | > 70% | SSM session → `du -sh /opt/openreplay/data/kafka` |
| RDS Connections | > 80% max | CloudWatch → RDS Metrics → DatabaseConnections |
| RDS Storage | > 80% | CloudWatch → RDS Metrics → FreeStorageSpace |
| Redis Memory | > 80% eviction | CloudWatch → ElastiCache Metrics |

### Rollback
```bash
# Disable OpenReplay (remove all infrastructure)
# Set enable_openreplay = false in terraform.tfvars, then
cd terraform && terraform plan -out=tfplan && terraform apply tfplan
```

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
