#!/bin/bash
# OpenReplay EC2 부트스트랩 스크립트
# Docker Compose로 OpenReplay를 기동하며, 외부 서비스(RDS, Redis, S3)를 사용
set -euo pipefail

REGION="${region}"
ENVIRONMENT="${environment}"
RDS_ENDPOINT="${rds_endpoint}"
REDIS_ENDPOINT="${elasticache_endpoint}"
S3_BUCKET="${s3_bucket}"

echo "=== OpenReplay 설치 시작 ==="

# 1. Docker + Docker Compose v2 설치
dnf update -y
dnf install -y docker git jq
systemctl enable docker
systemctl start docker

# Docker Compose v2 플러그인 설치
mkdir -p /usr/local/lib/docker/cli-plugins
COMPOSE_VERSION=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq -r '.tag_name')
curl -SL "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-aarch64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# 2. SSM에서 DB 비밀번호 읽기
DB_PASSWORD=$(aws ssm get-parameter \
  --name "/rum-pipeline/$${ENVIRONMENT}/openreplay/db-password" \
  --with-decryption \
  --region "$${REGION}" \
  --query 'Parameter.Value' \
  --output text)

# 3. JWT 시크릿 읽기/생성 (최초 실행 시 생성)
JWT_SECRET=$(aws ssm get-parameter \
  --name "/rum-pipeline/$${ENVIRONMENT}/openreplay/jwt-secret" \
  --with-decryption \
  --region "$${REGION}" \
  --query 'Parameter.Value' \
  --output text 2>/dev/null || true)

if [ -z "$${JWT_SECRET}" ]; then
  JWT_SECRET=$(openssl rand -hex 32)
  aws ssm put-parameter \
    --name "/rum-pipeline/$${ENVIRONMENT}/openreplay/jwt-secret" \
    --type SecureString \
    --value "$${JWT_SECRET}" \
    --region "$${REGION}"
fi

# 4. OpenReplay 리포지토리 클론
cd /opt
git clone https://github.com/openreplay/openreplay.git
cd openreplay

# 5. docker-compose.override.yml — 외부 서비스 사용 시 내장 컨테이너 비활성화
cat > docker-compose.override.yml << 'OVERRIDE'
services:
  postgresql:
    profiles: ["disabled"]
  redis:
    profiles: ["disabled"]
  minio:
    profiles: ["disabled"]
OVERRIDE

# 6. .env 파일 — 외부 서비스 엔드포인트 설정
cat > .env << ENV
# OpenReplay 환경 변수 (외부 서비스)
ENVIRONMENT=$${ENVIRONMENT}
AWS_REGION=$${REGION}

# PostgreSQL (RDS)
POSTGRES_HOST=$${RDS_ENDPOINT}
POSTGRES_PORT=5432
POSTGRES_DB=openreplay
POSTGRES_USER=openreplay
POSTGRES_PASSWORD=$${DB_PASSWORD}

# Redis (ElastiCache)
REDIS_HOST=$${REDIS_ENDPOINT}
REDIS_PORT=6379

# S3 (세션 녹화 저장)
S3_BUCKET=$${S3_BUCKET}
S3_REGION=$${REGION}

# JWT 시크릿
JWT_SECRET=$${JWT_SECRET}
ENV

# 7. Docker Compose 기동
docker compose up -d

echo "=== OpenReplay 설치 완료 ==="
