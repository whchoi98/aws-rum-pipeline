# terraform/modules/openreplay/main.tf
# CloudFront -> ALB -> EC2 (OpenReplay 세션 리플레이)

# --- Data Sources ---

data "aws_region" "current" {}

# CloudFront Managed Prefix List (ALB 인바운드 제한용)
data "aws_ec2_managed_prefix_list" "cloudfront" {
  name = "com.amazonaws.global.cloudfront.origin-facing"
}

# 최신 Amazon Linux 2023 x86_64 AMI (OpenReplay Docker 이미지가 amd64만 지원)
data "aws_ami" "al2023_x86" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
  }

  filter {
    name   = "architecture"
    values = ["x86_64"]
  }
}

# --- Security Groups ---

# ALB 보안 그룹 — CloudFront Prefix List에서만 80 포트 허용
resource "aws_security_group" "alb" {
  name_prefix = "${var.project_name}-or-alb-"
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

  tags = merge(var.tags, { Name = "${var.project_name}-or-alb-sg" })
}

# EC2 보안 그룹 — ALB SG에서 80(대시보드) + 9443(ingest) 허용
resource "aws_security_group" "ec2" {
  name_prefix = "${var.project_name}-or-ec2-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Dashboard from ALB"
  }

  ingress {
    from_port       = 9443
    to_port         = 9443
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Ingest from ALB"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.tags, { Name = "${var.project_name}-or-ec2-sg" })
}

# --- IAM ---

# EC2 인스턴스용 IAM 역할
resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-openreplay-ec2-role"

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

# S3 녹화 버킷 접근 정책
resource "aws_iam_role_policy" "s3_access" {
  name = "s3-recordings-access"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket"
      ]
      Resource = [
        aws_s3_bucket.recordings.arn,
        "${aws_s3_bucket.recordings.arn}/*"
      ]
    }]
  })
}

# SSM Parameter Store 읽기 정책 (OpenReplay 시크릿)
resource "aws_iam_role_policy" "ssm_read" {
  name = "ssm-openreplay-read"
  role = aws_iam_role.ec2.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "ssm:GetParameter",
        "ssm:GetParameters",
        "ssm:GetParametersByPath"
      ]
      Resource = "arn:aws:ssm:${data.aws_region.current.name}:${data.aws_caller_identity.current.account_id}:parameter/rum-pipeline/${var.environment}/openreplay/*"
    }]
  })
}

# SSM Managed Instance Core (Session Manager 접속용)
resource "aws_iam_role_policy_attachment" "ssm_core" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-openreplay-ec2-profile"
  role = aws_iam_role.ec2.name
}

# --- EC2 Instance ---

resource "aws_instance" "openreplay" {
  ami                    = data.aws_ami.al2023_x86.id
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
    region               = data.aws_region.current.name
  }))

  depends_on = [
    aws_db_instance.openreplay,
    aws_elasticache_cluster.openreplay
  ]

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay" })
}

# --- ALB ---

resource "aws_lb" "openreplay" {
  name               = "${var.project_name}-or-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  tags = merge(var.tags, { Name = "${var.project_name}-or-alb" })
}

# 대시보드 타겟 그룹 (포트 80)
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

# Ingest 타겟 그룹 (포트 9443)
resource "aws_lb_target_group" "ingest" {
  name     = "${var.project_name}-or-ingest-tg"
  port     = 9443
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

resource "aws_lb_target_group_attachment" "ingest" {
  target_group_arn = aws_lb_target_group.ingest.arn
  target_id        = aws_instance.openreplay.id
  port             = 9443
}

# HTTP 리스너 — 기본: 대시보드, /ingest/* 규칙: ingest 타겟 그룹
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
  priority     = 100

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

# --- CloudFront ---

resource "aws_cloudfront_distribution" "openreplay" {
  enabled     = true
  comment     = "OpenReplay Session Replay"
  price_class = "PriceClass_200"

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

  # /ingest/* — Lambda@Edge 인증 없이 통과 (SDK 데이터 수집용)
  ordered_cache_behavior {
    path_pattern     = "/ingest/*"
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 0
    max_ttl                = 0
  }

  # /* — 기본 동작 (대시보드). Lambda@Edge SSO 인증 연결 (활성화 시)
  default_cache_behavior {
    allowed_methods  = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "alb"

    forwarded_values {
      query_string = true
      headers      = ["*"]
      cookies {
        forward = "all"
      }
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

  tags = merge(var.tags, { Name = "${var.project_name}-or-cf" })
}
