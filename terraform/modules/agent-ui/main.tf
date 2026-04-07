# terraform/modules/agent-ui/main.tf
# CloudFront → ALB → EC2 (Next.js RUM Agent UI)

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
  name_prefix = "${var.project_name}-agent-alb-"
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
  tags = merge(var.tags, { Name = "${var.project_name}-agent-alb-sg" })
}

resource "aws_security_group" "ec2" {
  name_prefix = "${var.project_name}-agent-ec2-"
  vpc_id      = var.vpc_id

  ingress {
    from_port       = 3000
    to_port         = 3000
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  tags = merge(var.tags, { Name = "${var.project_name}-agent-ec2-sg" })
}

# --- IAM Role for EC2 ---

resource "aws_iam_role" "ec2" {
  name = "${var.project_name}-agent-ui-role"
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

resource "aws_iam_role_policy" "ec2_agentcore" {
  name = "agentcore-invoke"
  role = aws_iam_role.ec2.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock-agentcore:*", "bedrock:*"]
      Resource = "*"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ec2_ssm" {
  role       = aws_iam_role.ec2.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_instance_profile" "ec2" {
  name = "${var.project_name}-agent-ui-profile"
  role = aws_iam_role.ec2.name
}

# --- EC2 Instance ---

resource "aws_instance" "agent_ui" {
  ami                    = data.aws_ami.al2023_arm.id
  instance_type          = var.instance_type
  subnet_id              = var.public_subnet_ids[0]
  vpc_security_group_ids = [aws_security_group.ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.ec2.name

  user_data = base64encode(<<-USERDATA
    #!/bin/bash
    set -e

    # Install Node.js 20
    curl -fsSL https://rpm.nodesource.com/setup_20.x | bash -
    dnf install -y nodejs git

    # Clone and setup app
    mkdir -p /opt/rum-agent-ui
    cd /opt/rum-agent-ui

    # Create package.json and app files will be deployed via CodeDeploy or git
    cat > /opt/rum-agent-ui/.env << 'ENV'
    AWS_REGION=ap-northeast-2
    AGENTCORE_ENDPOINT_ARN=${var.agentcore_endpoint_arn}
    ENV

    echo "EC2 초기화 완료. Next.js 앱을 배포해 주세요."
  USERDATA
  )

  tags = merge(var.tags, { Name = "${var.project_name}-agent-ui" })
}

# --- ALB ---

resource "aws_lb" "agent" {
  name               = "${var.project_name}-agent-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb.id]
  subnets            = var.public_subnet_ids

  # SSE 스트리밍: Bedrock+Athena 멀티라운드 분석 시 최대 3분 소요
  idle_timeout = 180

  tags = merge(var.tags, { Name = "${var.project_name}-agent-alb" })
}

resource "aws_lb_target_group" "agent" {
  name     = "${var.project_name}-agent-tg"
  port     = 3000
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

resource "aws_lb_target_group_attachment" "agent" {
  target_group_arn = aws_lb_target_group.agent.arn
  target_id        = aws_instance.agent_ui.id
  port             = 3000
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.agent.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.agent.arn
  }
}

# --- CloudFront ---

resource "aws_cloudfront_distribution" "agent" {
  enabled     = true
  comment     = "RUM Agent UI"
  price_class = "PriceClass_200"

  origin {
    domain_name = aws_lb.agent.dns_name
    origin_id   = "alb"

    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_protocol_policy   = "http-only"
      origin_ssl_protocols     = ["TLSv1.2"]
      origin_read_timeout      = 60
      origin_keepalive_timeout = 60
    }
  }

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

  tags = merge(var.tags, { Name = "${var.project_name}-agent-cf" })
}
