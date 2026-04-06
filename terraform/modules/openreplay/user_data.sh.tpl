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
curl -SL "https://github.com/docker/compose/releases/download/$${COMPOSE_VERSION}/docker-compose-linux-x86_64" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# 2. SSM에서 시크릿 읽기 (Terraform이 미리 생성)
DB_PASSWORD=$(aws ssm get-parameter \
  --name "/rum-pipeline/$${ENVIRONMENT}/openreplay/db-password" \
  --with-decryption \
  --region "$${REGION}" \
  --query 'Parameter.Value' \
  --output text)

JWT_SECRET=$(aws ssm get-parameter \
  --name "/rum-pipeline/$${ENVIRONMENT}/openreplay/jwt-secret" \
  --with-decryption \
  --region "$${REGION}" \
  --query 'Parameter.Value' \
  --output text)

# 3. OpenReplay 리포지토리 클론
cd /opt
git clone https://github.com/openreplay/openreplay.git
cd openreplay/scripts/docker-compose

# 4. .env — Docker Compose 변수 치환용 (따옴표 없이)
cat > .env << ENV
COMMON_VERSION=v1.23.0
COMMON_PROTOCOL=https
COMMON_DOMAIN_NAME=localhost
COMMON_JWT_SECRET=$${JWT_SECRET}
COMMON_JWT_SPOT_SECRET=$${JWT_SECRET}
COMMON_S3_KEY=
COMMON_S3_SECRET=
COMMON_PG_PASSWORD=$${DB_PASSWORD}
COMMON_JWT_REFRESH_SECRET=$${JWT_SECRET}-refresh
COMMON_JWT_SPOT_REFRESH_SECRET=$${JWT_SECRET}-spot-refresh
COMMON_ASSIST_JWT_SECRET=$${JWT_SECRET}-assist
COMMON_ASSIST_KEY=$${JWT_SECRET}-assist-key
COMMON_TOKEN_SECRET=$${JWT_SECRET}-token
POSTGRES_VERSION=17
REDIS_VERSION=8
MINIO_VERSION=2025
CLICKHOUSE_VERSION=25.11-alpine
ENV
cp .env common.env

# 5. docker-compose.override.yml — 외부 서비스로 교체
cat > docker-compose.override.yml << 'OVERRIDE'
services:
  postgresql:
    profiles: ["disabled"]
  redis:
    profiles: ["disabled"]
  minio:
    profiles: ["disabled"]
OVERRIDE

# 6. DB 관련 환경변수 오버라이드 (docker-envs/db.env)
cat > docker-envs/db.env << DBENV
pg_host=$${RDS_ENDPOINT}
pg_port=5432
pg_dbname=openreplay
pg_user=openreplay
pg_password=$${DB_PASSWORD}
REDIS_STRING=redis://$${REDIS_ENDPOINT}:6379
S3_HOST=s3.amazonaws.com
S3_KEY=
S3_SECRET=
S3_BUCKET=$${S3_BUCKET}
AWS_DEFAULT_REGION=$${REGION}
DBENV

# 7. Docker Compose 기동
docker compose up -d

echo "=== OpenReplay 설치 완료 ==="
