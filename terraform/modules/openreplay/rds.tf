# terraform/modules/openreplay/rds.tf
# PostgreSQL 16 RDS 인스턴스 (OpenReplay 메타데이터 저장)

resource "aws_db_subnet_group" "openreplay" {
  name       = "${var.project_name}-openreplay-db"
  subnet_ids = var.private_subnet_ids

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-db-subnet" })
}

# RDS 보안 그룹 — EC2 SG에서만 5432 인바운드 허용
resource "aws_security_group" "rds" {
  name_prefix = "${var.project_name}-or-rds-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ec2.id]
    description     = "PostgreSQL from EC2 only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-or-rds-sg" })
}

# DB 비밀번호 자동 생성
resource "random_password" "db" {
  length  = 24
  special = false
}

# SSM Parameter Store에 비밀번호 저장
resource "aws_ssm_parameter" "db_password" {
  name  = "/rum-pipeline/${var.environment}/openreplay/db-password"
  type  = "SecureString"
  value = random_password.db.result

  tags = var.tags
}

# JWT 시크릿 자동 생성
resource "random_password" "jwt_secret" {
  length  = 64
  special = false
}

resource "aws_ssm_parameter" "jwt_secret" {
  name  = "/rum-pipeline/${var.environment}/openreplay/jwt-secret"
  type  = "SecureString"
  value = random_password.jwt_secret.result

  tags = var.tags
}

# RDS PostgreSQL 16 인스턴스
resource "aws_db_instance" "openreplay" {
  identifier     = "${var.project_name}-openreplay"
  engine         = "postgres"
  engine_version = "16"

  instance_class        = var.db_instance_class
  allocated_storage     = 20
  max_allocated_storage = 100
  storage_type          = "gp3"
  storage_encrypted     = true

  db_name  = "openreplay"
  username = "openreplay"
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.openreplay.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # 환경별 Multi-AZ 설정 (prod만 활성화)
  multi_az = var.environment == "prod"

  backup_retention_period = 7
  skip_final_snapshot     = true

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-db" })
}
