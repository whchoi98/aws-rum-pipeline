# OpenReplay Session Replay Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy self-hosted OpenReplay on AWS with CF → ALB → EC2 pattern, external RDS/ElastiCache/S3, and Cognito SSO auth.

**Architecture:** Independent Terraform module `openreplay/` + CDK Construct following existing `agent-ui` patterns. Docker Compose on EC2 (m7g.xlarge) with internal PostgreSQL/Redis/MinIO replaced by RDS/ElastiCache/S3.

**Tech Stack:** Terraform (HCL), AWS CDK (TypeScript), Docker Compose, OpenReplay self-hosted

---

## File Structure

### New Files
| Path | Responsibility |
|------|---------------|
| `terraform/modules/openreplay/variables.tf` | 모듈 입력 변수 |
| `terraform/modules/openreplay/s3.tf` | 세션 녹화 S3 버킷 + 라이프사이클 |
| `terraform/modules/openreplay/rds.tf` | RDS PostgreSQL + 서브넷 그룹 + SG |
| `terraform/modules/openreplay/elasticache.tf` | ElastiCache Redis + 서브넷 그룹 + SG |
| `terraform/modules/openreplay/main.tf` | CF, ALB, SG, EC2, IAM, user_data |
| `terraform/modules/openreplay/outputs.tf` | 모듈 출력 |
| `terraform/modules/openreplay/CLAUDE.md` | 모듈 문서 |
| `cdk/lib/constructs/openreplay.ts` | CDK Construct (Terraform 1:1) |
| `docs/decisions/ADR-007-openreplay-session-replay.md` | 아키텍처 결정 기록 |
| `docs/runbooks/14-openreplay-management.md` | 운영 런북 |

### Modified Files
| Path | Change |
|------|--------|
| `terraform/variables.tf` | `private_subnet_ids`, `enable_openreplay` 추가 |
| `terraform/main.tf` | `module "openreplay"` 호출 추가 |
| `terraform/outputs.tf` | OpenReplay 출력 추가 |
| `cdk/lib/rum-pipeline-stack.ts` | OpenReplay Construct 추가 |
| `docs/architecture.md` | Presentation Layer에 OpenReplay 추가 |
| `CLAUDE.md` | Project Structure에 openreplay 모듈 추가 |

---

### Task 1: Terraform 모듈 — variables.tf + S3

**Files:**
- Create: `terraform/modules/openreplay/variables.tf`
- Create: `terraform/modules/openreplay/s3.tf`

- [ ] **Step 1: Create variables.tf**

```hcl
# terraform/modules/openreplay/variables.tf
variable "project_name" {
  type = string
}
variable "environment" {
  type    = string
  default = "dev"
}
variable "vpc_id" {
  type = string
}
variable "public_subnet_ids" {
  type = list(string)
}
variable "private_subnet_ids" {
  type = list(string)
}
variable "instance_type" {
  type    = string
  default = "m7g.xlarge"
}
variable "db_instance_class" {
  type    = string
  default = "db.t4g.medium"
}
variable "edge_auth_qualified_arn" {
  description = "Lambda@Edge viewer-request ARN (빈 문자열이면 비활성)"
  type        = string
  default     = ""
}
variable "tags" {
  type    = map(string)
  default = {}
}
```

- [ ] **Step 2: Create s3.tf**

```hcl
# terraform/modules/openreplay/s3.tf
data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "recordings" {
  bucket = "${var.project_name}-openreplay-recordings-${data.aws_caller_identity.current.account_id}"
  tags   = merge(var.tags, { Name = "${var.project_name}-openreplay-recordings" })
}

resource "aws_s3_bucket_server_side_encryption_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "recordings" {
  bucket                  = aws_s3_bucket.recordings.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id
  rule {
    id     = "archive-and-expire"
    status = "Enabled"
    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 90
      storage_class = "GLACIER"
    }
    expiration {
      days = 365
    }
  }
}
```

- [ ] **Step 3: Validate**

Run: `cd terraform/modules/openreplay && terraform fmt && terraform validate`
Expected: Success

- [ ] **Step 4: Commit**

```bash
git add terraform/modules/openreplay/variables.tf terraform/modules/openreplay/s3.tf
git commit -m "feat(openreplay): add module variables and S3 recordings bucket"
```

---

### Task 2: Terraform 모듈 — RDS PostgreSQL

**Files:**
- Create: `terraform/modules/openreplay/rds.tf`

- [ ] **Step 1: Create rds.tf**

```hcl
# terraform/modules/openreplay/rds.tf

resource "aws_db_subnet_group" "openreplay" {
  name       = "${var.project_name}-openreplay-db"
  subnet_ids = var.private_subnet_ids
  tags       = merge(var.tags, { Name = "${var.project_name}-openreplay-db-subnet" })
}

resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-openreplay-rds-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
    description     = "EC2 only"
  }
  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-rds-sg" })
}

resource "aws_db_instance" "openreplay" {
  identifier     = "${var.project_name}-openreplay"
  engine         = "postgres"
  engine_version = "16"
  instance_class = var.db_instance_class

  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "openreplay"
  username = "openreplay"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.openreplay.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  multi_az            = var.environment == "prod" ? true : false
  backup_retention_period = 7
  skip_final_snapshot = true

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-db" })
}

resource "random_password" "db" {
  length  = 24
  special = false
}

resource "aws_ssm_parameter" "db_password" {
  name  = "/rum-pipeline/${var.environment}/openreplay/db-password"
  type  = "SecureString"
  value = random_password.db.result
  tags  = var.tags
}
```

- [ ] **Step 2: Validate**

Run: `cd terraform/modules/openreplay && terraform fmt`
Note: `terraform validate` will fail because `aws_security_group.ec2` is not yet defined (created in Task 4). This is expected.

- [ ] **Step 3: Commit**

```bash
git add terraform/modules/openreplay/rds.tf
git commit -m "feat(openreplay): add RDS PostgreSQL 16 with SSM password"
```

---

### Task 3: Terraform 모듈 — ElastiCache Redis

**Files:**
- Create: `terraform/modules/openreplay/elasticache.tf`

- [ ] **Step 1: Create elasticache.tf**

```hcl
# terraform/modules/openreplay/elasticache.tf

resource "aws_elasticache_subnet_group" "openreplay" {
  name       = "${var.project_name}-openreplay-redis"
  subnet_ids = var.private_subnet_ids
  tags       = var.tags
}

resource "aws_security_group" "redis" {
  name_prefix = "${var.project_name}-openreplay-redis-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
    description     = "EC2 only"
  }
  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-redis-sg" })
}

resource "aws_elasticache_cluster" "openreplay" {
  cluster_id      = "${var.project_name}-openreplay"
  engine          = "redis"
  engine_version  = "7.1"
  node_type       = "cache.t4g.micro"
  num_cache_nodes = 1

  subnet_group_name  = aws_elasticache_subnet_group.openreplay.name
  security_group_ids = [aws_security_group.redis.id]

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-redis" })
}
```

- [ ] **Step 2: Format and commit**

```bash
cd terraform/modules/openreplay && terraform fmt
git add terraform/modules/openreplay/elasticache.tf
git commit -m "feat(openreplay): add ElastiCache Redis 7.1"
```

---

### Task 4: Terraform 모듈 — main.tf (CF, ALB, SG, EC2, IAM)

**Files:**
- Create: `terraform/modules/openreplay/main.tf`

- [ ] **Step 1: Create main.tf with Security Groups**

```hcl
# terraform/modules/openreplay/main.tf
# CloudFront → ALB → EC2 (OpenReplay Docker Compose)

data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

data "aws_ami" "al2023_arm" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }
  filter {
    name   = "architecture"
    values = ["arm64"]
  }
}

# --- Security Groups ---

resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-openreplay-alb-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    prefix_list_ids = [data.aws_ec2_managed_prefix_list.cloudfront.id]
    description     = "CloudFront only"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-alb-sg" })
}

resource "aws_security_group" "ec2" {
  name_prefix = "${var.project_name}-openreplay-ec2-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Dashboard UI from ALB"
  }
  ingress {
    from_port       = 9443
    to_port         = 9443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Ingest API from ALB"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-ec2-sg" })
}
```

- [ ] **Step 2: Add IAM Role to main.tf**

Append to `main.tf`:

```hcl
# --- IAM Role ---

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-openreplay-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "s3_access" {
  name = "openreplay-s3"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:*"]
      Resource = [
        aws_s3_bucket.recordings.arn,
        "${aws_s3_bucket.recordings.arn}/*",
      ]
    }]
  })
}

resource "aws_iam_role_policy" "ssm_read" {
  name = "openreplay-ssm"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter", "ssm:GetParameters"]
      Resource = "arn:aws:ssm:*:*:parameter/rum-pipeline/${var.environment}/openreplay/*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-openreplay-profile"
  role = aws_iam_role.ec2.name
}
```

- [ ] **Step 3: Add EC2 Instance to main.tf**

Append to `main.tf`:

```hcl
# --- EC2 Instance ---

resource "aws_instance" "openreplay" {
  ami                    = data.aws_ami.al2023_arm.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  root_block_device {
    volume_size = 50
    volume_type = "gp3"
  }

  user_data = base64encode(templatefile("${path.module}/user_data.sh.tpl", {
    rds_endpoint         = aws_db_instance.openreplay.address
    elasticache_endpoint = aws_elasticache_cluster.openreplay.cache_nodes[0].address
    s3_bucket            = aws_s3_bucket.recordings.id
    environment          = var.environment
    region               = "ap-northeast-2"
  }))

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay" })

  depends_on = [
    aws_db_instance.openreplay,
    aws_elasticache_cluster.openreplay,
  ]
}
```

- [ ] **Step 4: Create user_data.sh.tpl**

Create `terraform/modules/openreplay/user_data.sh.tpl`:

```bash
#!/bin/bash
set -euo pipefail

# --- Docker 설치 ---
dnf install -y docker git
systemctl enable docker && systemctl start docker

# Docker Compose v2 플러그인 설치
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" \
  -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

# --- SSM에서 시크릿 읽기 ---
DB_PASSWORD=$(aws ssm get-parameter \
  --name "/rum-pipeline/${environment}/openreplay/db-password" \
  --with-decryption --query 'Parameter.Value' --output text \
  --region ${region})

JWT_SECRET=$(aws ssm get-parameter \
  --name "/rum-pipeline/${environment}/openreplay/jwt-secret" \
  --with-decryption --query 'Parameter.Value' --output text \
  --region ${region} 2>/dev/null || openssl rand -hex 32)

# JWT_SECRET이 SSM에 없으면 생성하여 저장
if ! aws ssm get-parameter --name "/rum-pipeline/${environment}/openreplay/jwt-secret" --region ${region} 2>/dev/null; then
  aws ssm put-parameter \
    --name "/rum-pipeline/${environment}/openreplay/jwt-secret" \
    --value "$JWT_SECRET" --type SecureString \
    --region ${region}
fi

# --- OpenReplay 설치 ---
mkdir -p /opt/openreplay && cd /opt/openreplay
git clone https://github.com/openreplay/openreplay.git .
cd scripts/helmcharts/docker-compose

# --- Override: 외부 서비스 연결 ---
cat > docker-compose.override.yml << 'OVERRIDE'
services:
  postgresql:
    profiles: ["disabled"]
  redis:
    profiles: ["disabled"]
  minio:
    profiles: ["disabled"]
OVERRIDE

# --- 환경 변수 설정 ---
cat > .env << ENV
DOMAIN_NAME=localhost
pg_host=${rds_endpoint}
pg_port=5432
pg_dbname=openreplay
pg_user=openreplay
pg_password=$DB_PASSWORD
REDIS_HOST=${elasticache_endpoint}
REDIS_PORT=6379
S3_BUCKET_NAME=${s3_bucket}
AWS_DEFAULT_REGION=${region}
JWT_SECRET=$JWT_SECRET
ENTERPRISE_BUILD=false
ENV

# --- 시작 ---
docker compose up -d

echo "OpenReplay 설치 완료"
```

- [ ] **Step 5: Add ALB to main.tf**

Append to `main.tf`:

```hcl
# --- ALB ---

resource "aws_lb" "openreplay" {
  name               = "${var.project_name}-or-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-alb" })
}

# Dashboard UI (포트 80)
resource "aws_lb_target_group" "dashboard" {
  name     = "${var.project_name}-or-dash-tg"
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
  tags = var.tags
}

resource "aws_lb_target_group_attachment" "dashboard" {
  target_group_arn = aws_lb_target_group.dashboard.arn
  target_id        = aws_instance.openreplay.id
  port             = 80
}

# Ingest API (포트 9443)
resource "aws_lb_target_group" "ingest" {
  name     = "${var.project_name}-or-ing-tg"
  port     = 9443
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  health_check {
    path                = "/healthz"
    healthy_threshold   = 2
    unhealthy_threshold = 3
    timeout             = 5
    interval            = 30
  }
  tags = var.tags
}

resource "aws_lb_target_group_attachment" "ingest" {
  target_group_arn = aws_lb_target_group.ingest.arn
  target_id        = aws_instance.openreplay.id
  port             = 9443
}

# ALB Listener: 경로 기반 라우팅
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.openreplay.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.dashboard.arn
  }
}

resource "aws_lb_listener_rule" "ingest" {
  listener_arn = aws_lb_listener.http.arn
  priority     = 10

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ingest.arn
  }
  condition {
    path_pattern {
      values = ["/ingest/*"]
    }
  }
}
```

- [ ] **Step 6: Add CloudFront to main.tf**

Append to `main.tf`:

```hcl
# --- CloudFront ---

resource "aws_cloudfront_distribution" "openreplay" {
  enabled     = true
  comment     = "OpenReplay Session Replay"
  price_class = "PriceClass_200"

  # Origin: ALB
  origin {
    domain_name = aws_lb.openreplay.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "http-only"
      origin_ssl_protocols   = ["TLSv1.2"]
    }
  }

  # /ingest/* — 인증 없음 (트래커 데이터)
  ordered_cache_behavior {
    path_pattern     = "/ingest/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  # /* — SSO 인증 (대시보드)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies { forward = "all" }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0

    dynamic "lambda_function_association" {
      for_each = var.edge_auth_qualified_arn != "" ? [1] : []
      content {
        event_type   = "viewer-request"
        lambda_arn   = var.edge_auth_qualified_arn
        include_body = false
      }
    }
  }

  viewer_certificate {
    cloudfront_default_certificate = true
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-cf" })
}
```

- [ ] **Step 7: Validate and commit**

```bash
cd terraform/modules/openreplay && terraform fmt -recursive
git add terraform/modules/openreplay/main.tf terraform/modules/openreplay/user_data.sh.tpl
git commit -m "feat(openreplay): add CF, ALB, SG, EC2, IAM with Docker Compose user_data"
```

---

### Task 5: Terraform 모듈 — outputs.tf

**Files:**
- Create: `terraform/modules/openreplay/outputs.tf`

- [ ] **Step 1: Create outputs.tf**

```hcl
# terraform/modules/openreplay/outputs.tf
output "cloudfront_domain" {
  description = "OpenReplay 대시보드 CloudFront 도메인"
  value       = aws_cloudfront_distribution.openreplay.domain_name
}

output "ingest_endpoint" {
  description = "OpenReplay 트래커 ingest URL"
  value       = "https://${aws_cloudfront_distribution.openreplay.domain_name}/ingest"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL 엔드포인트"
  value       = aws_db_instance.openreplay.address
}

output "s3_bucket_name" {
  description = "세션 녹화 S3 버킷명"
  value       = aws_s3_bucket.recordings.id
}
```

- [ ] **Step 2: Format, validate, commit**

```bash
cd terraform/modules/openreplay && terraform fmt
terraform validate
git add terraform/modules/openreplay/outputs.tf
git commit -m "feat(openreplay): add module outputs"
```

---

### Task 6: Root Terraform 통합

**Files:**
- Modify: `terraform/variables.tf`
- Modify: `terraform/main.tf`
- Modify: `terraform/outputs.tf`

- [ ] **Step 1: Add variables to terraform/variables.tf**

Append after `allowed_origins` variable:

```hcl
variable "private_subnet_ids" {
  description = "Private subnet IDs for RDS and ElastiCache (OpenReplay)"
  type        = list(string)
  default     = []
}

variable "enable_openreplay" {
  description = "OpenReplay 세션 리플레이 활성화 여부"
  type        = bool
  default     = false
}
```

- [ ] **Step 2: Add module call to terraform/main.tf**

Append after `module "agent_ui"` block:

```hcl
# -----------------------------------------------------------------------------
# Session Replay — OpenReplay (CloudFront + ALB + EC2 + RDS + ElastiCache + S3)
# -----------------------------------------------------------------------------

module "openreplay" {
  count  = var.enable_openreplay ? 1 : 0
  source = "./modules/openreplay"

  project_name            = var.project_name
  environment             = var.environment
  vpc_id                  = var.vpc_id
  public_subnet_ids       = var.public_subnet_ids
  private_subnet_ids      = var.private_subnet_ids
  instance_type           = "m7g.xlarge"
  edge_auth_qualified_arn = module.auth.edge_auth_qualified_arn
  tags                    = { Component = "session-replay" }
}
```

- [ ] **Step 3: Add outputs to terraform/outputs.tf**

Append:

```hcl
output "openreplay_cloudfront_domain" {
  description = "OpenReplay dashboard URL"
  value       = var.enable_openreplay ? module.openreplay[0].cloudfront_domain : null
}

output "openreplay_ingest_endpoint" {
  description = "OpenReplay tracker ingest endpoint"
  value       = var.enable_openreplay ? module.openreplay[0].ingest_endpoint : null
}
```

- [ ] **Step 4: Format and commit**

```bash
cd terraform && terraform fmt -recursive
git add terraform/variables.tf terraform/main.tf terraform/outputs.tf
git commit -m "feat(openreplay): integrate module into root Terraform (enable_openreplay flag)"
```

---

### Task 7: CDK Construct

**Files:**
- Create: `cdk/lib/constructs/openreplay.ts`

- [ ] **Step 1: Create openreplay.ts**

```typescript
import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as elasticache from 'aws-cdk-lib/aws-elasticache';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as elbv2_targets from 'aws-cdk-lib/aws-elasticloadbalancingv2-targets';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as origins from 'aws-cdk-lib/aws-cloudfront-origins';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';

export interface OpenReplayProps {
  projectName: string;
  environment: string;
  vpcId: string;
  publicSubnetIds: string[];
  privateSubnetIds: string[];
  instanceType?: string;
  dbInstanceClass?: string;
  edgeAuthFunction?: cloudfront.experimental.EdgeFunction;
}

export class OpenReplay extends Construct {
  public readonly cloudfrontDomain: string;
  public readonly ingestEndpoint: string;

  constructor(scope: Construct, id: string, props: OpenReplayProps) {
    super(scope, id);

    const {
      projectName,
      environment: envName,
      vpcId,
      publicSubnetIds,
      privateSubnetIds,
      instanceType = 'm7g.xlarge',
      dbInstanceClass = 'db.t4g.medium',
    } = props;

    const vpc = ec2.Vpc.fromLookup(this, 'Vpc', { vpcId });
    const publicSubnets = publicSubnetIds.map((id, i) =>
      ec2.Subnet.fromSubnetId(this, `PubSub${i}`, id),
    );
    const privateSubnets = privateSubnetIds.map((id, i) =>
      ec2.Subnet.fromSubnetId(this, `PriSub${i}`, id),
    );

    // ─── S3 녹화 버킷 ───
    const recordingsBucket = new s3.Bucket(this, 'RecordingsBucket', {
      bucketName: `${projectName}-openreplay-recordings-${cdk.Aws.ACCOUNT_ID}`,
      encryption: s3.BucketEncryption.S3_MANAGED,
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL,
      lifecycleRules: [
        {
          transitions: [
            { storageClass: s3.StorageClass.INFREQUENT_ACCESS, transitionAfter: cdk.Duration.days(30) },
            { storageClass: s3.StorageClass.GLACIER, transitionAfter: cdk.Duration.days(90) },
          ],
          expiration: cdk.Duration.days(365),
        },
      ],
    });

    // ─── Security Groups ───
    const albSg = new ec2.SecurityGroup(this, 'AlbSg', {
      vpc, description: 'OpenReplay ALB - CloudFront only', allowAllOutbound: true,
    });
    albSg.addIngressRule(
      ec2.Peer.prefixList('pl-22a6434b'),
      ec2.Port.tcp(80), 'CloudFront only',
    );

    const ec2Sg = new ec2.SecurityGroup(this, 'Ec2Sg', {
      vpc, description: 'OpenReplay EC2', allowAllOutbound: true,
    });
    ec2Sg.addIngressRule(albSg, ec2.Port.tcp(80), 'Dashboard from ALB');
    ec2Sg.addIngressRule(albSg, ec2.Port.tcp(9443), 'Ingest from ALB');

    const rdsSg = new ec2.SecurityGroup(this, 'RdsSg', {
      vpc, description: 'OpenReplay RDS', allowAllOutbound: false,
    });
    rdsSg.addIngressRule(ec2Sg, ec2.Port.tcp(5432), 'EC2 only');

    const redisSg = new ec2.SecurityGroup(this, 'RedisSg', {
      vpc, description: 'OpenReplay Redis', allowAllOutbound: false,
    });
    redisSg.addIngressRule(ec2Sg, ec2.Port.tcp(6379), 'EC2 only');

    // ─── RDS PostgreSQL ───
    const dbPassword = new cdk.SecretValue(cdk.Fn.join('', [
      '{{resolve:ssm-secure:/rum-pipeline/', envName, '/openreplay/db-password}}',
    ]));

    const dbInstance = new rds.DatabaseInstance(this, 'Database', {
      engine: rds.DatabaseInstanceEngine.postgres({ version: rds.PostgresEngineVersion.VER_16 }),
      instanceType: new ec2.InstanceType(dbInstanceClass),
      vpc,
      vpcSubnets: { subnets: privateSubnets },
      securityGroups: [rdsSg],
      databaseName: 'openreplay',
      credentials: rds.Credentials.fromPassword('openreplay', dbPassword),
      allocatedStorage: 20,
      maxAllocatedStorage: 100,
      storageEncrypted: true,
      backupRetention: cdk.Duration.days(7),
      removalPolicy: cdk.RemovalPolicy.DESTROY,
    });

    // ─── ElastiCache Redis ───
    const redisSubnetGroup = new elasticache.CfnSubnetGroup(this, 'RedisSubnetGroup', {
      description: 'OpenReplay Redis',
      subnetIds: privateSubnetIds,
      cacheSubnetGroupName: `${projectName}-openreplay-redis`,
    });

    const redisCluster = new elasticache.CfnCacheCluster(this, 'RedisCluster', {
      clusterName: `${projectName}-openreplay`,
      engine: 'redis',
      engineVersion: '7.1',
      cacheNodeType: 'cache.t4g.micro',
      numCacheNodes: 1,
      cacheSubnetGroupName: redisSubnetGroup.cacheSubnetGroupName!,
      vpcSecurityGroupIds: [redisSg.securityGroupId],
    });
    redisCluster.addDependency(redisSubnetGroup);

    // ─── EC2 IAM Role ───
    const role = new iam.Role(this, 'Ec2Role', {
      assumedBy: new iam.ServicePrincipal('ec2.amazonaws.com'),
      managedPolicies: [
        iam.ManagedPolicy.fromAwsManagedPolicyName('AmazonSSMManagedInstanceCore'),
      ],
    });
    recordingsBucket.grantReadWrite(role);
    role.addToPolicy(new iam.PolicyStatement({
      actions: ['ssm:GetParameter', 'ssm:GetParameters'],
      resources: [`arn:aws:ssm:*:*:parameter/rum-pipeline/${envName}/openreplay/*`],
    }));

    // ─── EC2 Instance ───
    const instance = new ec2.Instance(this, 'Instance', {
      vpc,
      instanceType: new ec2.InstanceType(instanceType),
      machineImage: ec2.MachineImage.latestAmazonLinux2023({ cpuType: ec2.AmazonLinuxCpuType.ARM_64 }),
      securityGroup: ec2Sg,
      role,
      vpcSubnets: { subnets: publicSubnets },
      blockDevices: [{ deviceName: '/dev/xvda', volume: ec2.BlockDeviceVolume.ebs(50, { volumeType: ec2.EbsDeviceVolumeType.GP3 }) }],
      userData: ec2.UserData.custom(`#!/bin/bash
set -euo pipefail
dnf install -y docker git
systemctl enable docker && systemctl start docker
mkdir -p /usr/local/lib/docker/cli-plugins
curl -SL "https://github.com/docker/compose/releases/latest/download/docker-compose-linux-$(uname -m)" -o /usr/local/lib/docker/cli-plugins/docker-compose
chmod +x /usr/local/lib/docker/cli-plugins/docker-compose

DB_PASSWORD=$(aws ssm get-parameter --name "/rum-pipeline/${envName}/openreplay/db-password" --with-decryption --query 'Parameter.Value' --output text --region ${cdk.Aws.REGION})
JWT_SECRET=$(aws ssm get-parameter --name "/rum-pipeline/${envName}/openreplay/jwt-secret" --with-decryption --query 'Parameter.Value' --output text --region ${cdk.Aws.REGION} 2>/dev/null || openssl rand -hex 32)

mkdir -p /opt/openreplay && cd /opt/openreplay
git clone https://github.com/openreplay/openreplay.git .
cd scripts/helmcharts/docker-compose

cat > docker-compose.override.yml << 'OVR'
services:
  postgresql:
    profiles: ["disabled"]
  redis:
    profiles: ["disabled"]
  minio:
    profiles: ["disabled"]
OVR

cat > .env << ENV
DOMAIN_NAME=localhost
pg_host=${dbInstance.dbInstanceEndpointAddress}
pg_port=5432
pg_dbname=openreplay
pg_user=openreplay
pg_password=$DB_PASSWORD
REDIS_HOST=${cdk.Fn.getAtt(redisCluster.logicalId, 'RedisEndpoint.Address').toString()}
REDIS_PORT=6379
S3_BUCKET_NAME=${recordingsBucket.bucketName}
AWS_DEFAULT_REGION=${cdk.Aws.REGION}
JWT_SECRET=$JWT_SECRET
ENTERPRISE_BUILD=false
ENV

docker compose up -d
`),
    });

    // ─── ALB ───
    const alb = new elbv2.ApplicationLoadBalancer(this, 'Alb', {
      vpc, internetFacing: true, securityGroup: albSg,
      vpcSubnets: { subnets: publicSubnets },
    });

    const dashTg = new elbv2.ApplicationTargetGroup(this, 'DashTg', {
      vpc, port: 80, protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [new elbv2_targets.InstanceTarget(instance, 80)],
      healthCheck: { path: '/', interval: cdk.Duration.seconds(30) },
    });

    const ingestTg = new elbv2.ApplicationTargetGroup(this, 'IngestTg', {
      vpc, port: 9443, protocol: elbv2.ApplicationProtocol.HTTP,
      targets: [new elbv2_targets.InstanceTarget(instance, 9443)],
      healthCheck: { path: '/healthz', interval: cdk.Duration.seconds(30) },
    });

    const listener = alb.addListener('Http', { port: 80, defaultTargetGroups: [dashTg] });
    listener.addTargetGroups('IngestRule', {
      targetGroups: [ingestTg],
      priority: 10,
      conditions: [elbv2.ListenerCondition.pathPatterns(['/ingest/*'])],
    });

    // ─── CloudFront ───
    const albOrigin = new origins.HttpOrigin(alb.loadBalancerDnsName, {
      protocolPolicy: cloudfront.OriginProtocolPolicy.HTTP_ONLY,
    });

    const edgeLambdas: cloudfront.EdgeLambda[] = [];
    if (props.edgeAuthFunction) {
      edgeLambdas.push({
        eventType: cloudfront.LambdaEdgeEventType.VIEWER_REQUEST,
        functionVersion: props.edgeAuthFunction.currentVersion,
        includeBody: false,
      });
    }

    const distribution = new cloudfront.Distribution(this, 'Distribution', {
      defaultBehavior: {
        origin: albOrigin,
        viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
        allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
        cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
        originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
        edgeLambdas: edgeLambdas.length > 0 ? edgeLambdas : undefined,
      },
      additionalBehaviors: {
        '/ingest/*': {
          origin: albOrigin,
          viewerProtocolPolicy: cloudfront.ViewerProtocolPolicy.REDIRECT_TO_HTTPS,
          allowedMethods: cloudfront.AllowedMethods.ALLOW_ALL,
          cachePolicy: cloudfront.CachePolicy.CACHING_DISABLED,
          originRequestPolicy: cloudfront.OriginRequestPolicy.ALL_VIEWER,
          // /ingest/*에는 Lambda@Edge 인증 없음
        },
      },
      priceClass: cloudfront.PriceClass.PRICE_CLASS_200,
    });

    this.cloudfrontDomain = distribution.distributionDomainName;
    this.ingestEndpoint = `https://${distribution.distributionDomainName}/ingest`;

    new cdk.CfnOutput(this, 'OpenReplayUrl', {
      value: `https://${this.cloudfrontDomain}`,
      description: 'OpenReplay Dashboard URL',
    });
    new cdk.CfnOutput(this, 'IngestEndpoint', {
      value: this.ingestEndpoint,
      description: 'OpenReplay Tracker Ingest Endpoint',
    });
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add cdk/lib/constructs/openreplay.ts
git commit -m "feat(openreplay): add CDK Construct (1:1 Terraform mapping)"
```

---

### Task 8: CDK Stack 통합

**Files:**
- Modify: `cdk/lib/rum-pipeline-stack.ts`

- [ ] **Step 1: Add import and OpenReplay construct**

Add import at top of file:

```typescript
import { OpenReplay } from './constructs/openreplay';
```

Add `privateSubnetIds?: string[]` to `RumPipelineStackProps`.

Add after the Agent UI block (inside the `if (vpcId && publicSubnetIds...)` conditional):

```typescript
      // ─── 11. OpenReplay Session Replay (선택) ───
      const privateSubnetIds = this.node.tryGetContext('privateSubnetIds') as string[] | undefined;
      if (privateSubnetIds) {
        const openReplay = new OpenReplay(this, 'OpenReplay', {
          projectName,
          environment: envName,
          vpcId,
          publicSubnetIds,
          privateSubnetIds,
        });

        new cdk.CfnOutput(this, 'OpenReplayDashboard', {
          value: `https://${openReplay.cloudfrontDomain}`,
          description: 'OpenReplay Session Replay 대시보드',
        });
      }
```

- [ ] **Step 2: Commit**

```bash
git add cdk/lib/rum-pipeline-stack.ts
git commit -m "feat(openreplay): integrate Construct into CDK stack"
```

---

### Task 9: Module CLAUDE.md

**Files:**
- Create: `terraform/modules/openreplay/CLAUDE.md`

- [ ] **Step 1: Create CLAUDE.md**

```markdown
<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## OpenReplay Module

### Role
OpenReplay 셀프호스팅 세션 리플레이를 CF → ALB → EC2 아키텍처로 배포.
RDS PostgreSQL, ElastiCache Redis, S3를 외부 관리형 서비스로 사용.

### Key Resources
| 리소스 | 역할 |
|--------|------|
| `aws_cloudfront_distribution` | HTTPS + SSO 인증 + /ingest 라우팅 |
| `aws_lb` | ALB — CF Prefix List SG |
| `aws_instance` | m7g.xlarge — Docker Compose (OpenReplay) |
| `aws_db_instance` | RDS PostgreSQL 16 |
| `aws_elasticache_cluster` | Redis 7.1 |
| `aws_s3_bucket` | 세션 녹화 데이터 |

### Rules
- `enable_openreplay = true` + `private_subnet_ids` 필수
- EC2 user_data로 Docker Compose 자동 설치
- 시크릿은 SSM Parameter Store에서 읽음 (하드코딩 금지)
- /ingest/* 경로는 인증 없음 (트래커 데이터 수집)
- /* 경로는 Lambda@Edge SSO 인증

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## OpenReplay Module

### Role
Deploys self-hosted OpenReplay session replay via CF → ALB → EC2 architecture.
Uses RDS PostgreSQL, ElastiCache Redis, and S3 as external managed services.

### Key Resources
| Resource | Role |
|----------|------|
| `aws_cloudfront_distribution` | HTTPS + SSO auth + /ingest routing |
| `aws_lb` | ALB — CF Prefix List SG |
| `aws_instance` | m7g.xlarge — Docker Compose (OpenReplay) |
| `aws_db_instance` | RDS PostgreSQL 16 |
| `aws_elasticache_cluster` | Redis 7.1 |
| `aws_s3_bucket` | Session recording data |

### Rules
- Requires `enable_openreplay = true` + `private_subnet_ids`
- EC2 user_data auto-installs Docker Compose
- Secrets read from SSM Parameter Store (no hardcoding)
- /ingest/* path has no auth (tracker data collection)
- /* path protected by Lambda@Edge SSO

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
```

- [ ] **Step 2: Commit**

```bash
git add terraform/modules/openreplay/CLAUDE.md
git commit -m "docs: add OpenReplay module CLAUDE.md"
```

---

### Task 10: ADR-007

**Files:**
- Create: `docs/decisions/ADR-007-openreplay-session-replay.md`

- [ ] **Step 1: Create ADR**

```markdown
<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

# ADR-007: OpenReplay 셀프호스팅 세션 리플레이

## Status
Accepted

## Context
RUM 이벤트 수집(성능, 에러)은 구현되었으나 세션 리플레이(DOM 녹화/재생) 기능이 없음.
사용자 행동을 시각적으로 재현하여 디버깅 및 UX 분석 효율을 높일 필요가 있음.
rrweb 자체 구현 vs OpenReplay 셀프호스팅 vs 상용 SaaS 중 선택 필요.

## Decision
- OpenReplay를 셀프호스팅으로 배포 (Docker Compose on EC2)
- 기존 RUM SDK와 병행 운영 (세션 ID 연동 없이 독립 운영)
- CF → CF Prefix List SG → ALB → EC2 패턴 (agent-ui와 동일)
- 핵심 스토리지를 AWS 관리형 서비스로 분리 (RDS, ElastiCache, S3)
- 기존 Cognito SSO + Lambda@Edge 인증 재사용
- Terraform 독립 모듈 + CDK Construct로 관리

## Consequences
- **장점**: 즉시 사용 가능한 세션 재생 UI, 오픈소스 커뮤니티 지원, 기존 파이프라인 무영향
- **단점**: 추가 인프라 비용 (~$210/월), Docker Compose 운영 부담, OpenReplay 버전 업그레이드 수동

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

# ADR-007: Self-Hosted OpenReplay Session Replay

## Status
Accepted

## Context
RUM event collection (performance, errors) is implemented, but session replay (DOM recording/playback) is missing.
Visual reproduction of user behavior is needed to improve debugging and UX analysis efficiency.
Choice between custom rrweb implementation, self-hosted OpenReplay, and commercial SaaS.

## Decision
- Deploy OpenReplay as self-hosted (Docker Compose on EC2)
- Parallel operation with existing RUM SDK (independent, no session ID linking)
- CF → CF Prefix List SG → ALB → EC2 pattern (same as agent-ui)
- Core storage on AWS managed services (RDS, ElastiCache, S3)
- Reuse existing Cognito SSO + Lambda@Edge authentication
- Managed as independent Terraform module + CDK Construct

## Consequences
- **Pros**: Ready-to-use session replay UI, open-source community support, no impact on existing pipeline
- **Cons**: Additional infrastructure cost (~$210/month), Docker Compose operational overhead, manual OpenReplay version upgrades

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
```

- [ ] **Step 2: Commit**

```bash
git add docs/decisions/ADR-007-openreplay-session-replay.md
git commit -m "docs: add ADR-007 OpenReplay session replay"
```

---

### Task 11: Runbook

**Files:**
- Create: `docs/runbooks/14-openreplay-management.md`

- [ ] **Step 1: Create runbook**

```markdown
<p align="center">
  <a href="#-한국어"><kbd>🇰🇷 한국어</kbd></a>&nbsp;&nbsp;&nbsp;
  <a href="#-english"><kbd>🇺🇸 English</kbd></a>
</p>

# 🇰🇷 한국어

## 런북: OpenReplay 운영 관리

### 개요
OpenReplay 셀프호스팅 인스턴스의 상태 확인, 업그레이드, 복구 절차.

### 사전 조건
- AWS CLI + SSM Session Manager 접근 가능
- EC2 인스턴스 ID (`terraform output -module=openreplay`)

### 절차

#### 상태 확인

```bash
# EC2 접속
aws ssm start-session --target <instance-id>

# Docker 상태 확인
cd /opt/openreplay/scripts/helmcharts/docker-compose
docker compose ps
docker compose logs --tail=50

# 디스크 사용량 (Kafka 로그)
df -h /var/lib/docker
```

#### OpenReplay 버전 업그레이드

```bash
aws ssm start-session --target <instance-id>
cd /opt/openreplay
git fetch && git checkout <new-version-tag>
cd scripts/helmcharts/docker-compose
docker compose pull
docker compose up -d
docker compose logs -f  # 에러 확인
```

#### EC2 교체 (장애 복구)

```bash
# 1. Terraform으로 EC2 재생성
cd terraform
terraform taint 'module.openreplay[0].aws_instance.openreplay'
terraform apply

# 2. user_data가 자동으로 Docker Compose 재설치
# 3. 데이터 무손실 (RDS/S3는 외부 관리형)
```

#### RDS 스냅샷 복원

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier rum-pipeline-openreplay-restored \
  --db-snapshot-identifier <snapshot-id>
```

### 모니터링
- EC2 CPU/메모리: CloudWatch 기본 메트릭
- Kafka 디스크: `/var/lib/docker` 70% 초과 시 알람 설정 권장
- RDS 연결: CloudWatch `DatabaseConnections` 메트릭

<p align="right"><a href="#-english">🇺🇸 English ↓</a></p>

# 🇺🇸 English

## Runbook: OpenReplay Operations Management

### Overview
Status check, upgrade, and recovery procedures for the self-hosted OpenReplay instance.

### Prerequisites
- AWS CLI + SSM Session Manager access
- EC2 instance ID (`terraform output -module=openreplay`)

### Procedures

#### Health Check

```bash
# Connect to EC2
aws ssm start-session --target <instance-id>

# Docker status
cd /opt/openreplay/scripts/helmcharts/docker-compose
docker compose ps
docker compose logs --tail=50

# Disk usage (Kafka logs)
df -h /var/lib/docker
```

#### OpenReplay Version Upgrade

```bash
aws ssm start-session --target <instance-id>
cd /opt/openreplay
git fetch && git checkout <new-version-tag>
cd scripts/helmcharts/docker-compose
docker compose pull
docker compose up -d
docker compose logs -f  # Check for errors
```

#### EC2 Replacement (Disaster Recovery)

```bash
# 1. Recreate EC2 via Terraform
cd terraform
terraform taint 'module.openreplay[0].aws_instance.openreplay'
terraform apply

# 2. user_data auto-reinstalls Docker Compose
# 3. No data loss (RDS/S3 are external managed services)
```

#### RDS Snapshot Restore

```bash
aws rds restore-db-instance-from-db-snapshot \
  --db-instance-identifier rum-pipeline-openreplay-restored \
  --db-snapshot-identifier <snapshot-id>
```

### Monitoring
- EC2 CPU/memory: CloudWatch default metrics
- Kafka disk: alarm recommended when `/var/lib/docker` exceeds 70%
- RDS connections: CloudWatch `DatabaseConnections` metric

<p align="right"><a href="#-한국어">🇰🇷 한국어 ↑</a></p>
```

- [ ] **Step 2: Commit**

```bash
git add docs/runbooks/14-openreplay-management.md
git commit -m "docs: add runbook 14 — OpenReplay management"
```

---

### Task 12: 문서 업데이트 (architecture.md, CLAUDE.md)

**Files:**
- Modify: `docs/architecture.md` — Presentation Layer에 OpenReplay 추가 (한국어/영어 양쪽)
- Modify: `CLAUDE.md` — Project Structure에 openreplay 모듈 추가 (한국어/영어 양쪽)

- [ ] **Step 1: Update docs/architecture.md**

한국어 Components 섹션의 Observability Layer 아래에 추가:

```markdown
### Session Replay
- **terraform/modules/openreplay/** — OpenReplay 셀프호스팅 인프라. CF → ALB → EC2 (Docker Compose).
  - EC2에서 Kafka, 프론트엔드, 백엔드 컨테이너 실행.
  - RDS PostgreSQL, ElastiCache Redis, S3 녹화 버킷을 외부 관리형으로 사용.
  - `/ingest/*` 경로로 트래커 데이터 수집 (인증 없음), `/*` 대시보드 (SSO).
```

영어 Components 섹션에도 동일 내용 추가.

- [ ] **Step 2: Update CLAUDE.md Project Structure**

한국어 섹션의 `terraform/modules/` 하위에 추가:

```
    openreplay/   - OpenReplay 세션 리플레이 (CF → ALB → EC2 + RDS + Redis + S3)
```

영어 섹션에도 동일 추가:

```
    openreplay/   - OpenReplay session replay (CF → ALB → EC2 + RDS + Redis + S3)
```

- [ ] **Step 3: Commit**

```bash
git add docs/architecture.md CLAUDE.md
git commit -m "docs: update architecture and CLAUDE.md with OpenReplay module"
```
