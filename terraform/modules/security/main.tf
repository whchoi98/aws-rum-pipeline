# terraform/modules/security/main.tf

# -----------------------------------------------------------------------------
# WAF WebACL
# -----------------------------------------------------------------------------

resource "aws_wafv2_web_acl" "rum" {
  name        = "${var.project_name}-waf"
  scope       = "REGIONAL"
  description = "WAF for RUM pipeline API"

  default_action {
    allow {}
  }

  rule {
    name     = "rate-limit"
    priority = 0

    action {
      block {}
    }

    statement {
      rate_based_statement {
        limit              = var.rate_limit
        aggregate_key_type = "IP"
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-rate-limit"
    }
  }

  rule {
    name     = "bot-control"
    priority = 1

    override_action {
      none {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesBotControlRuleSet"
        vendor_name = "AWS"

        managed_rule_group_configs {
          aws_managed_rules_bot_control_rule_set {
            inspection_level = "COMMON"
          }
        }
      }
    }

    visibility_config {
      sampled_requests_enabled   = true
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.project_name}-bot-control"
    }
  }

  visibility_config {
    sampled_requests_enabled   = true
    cloudwatch_metrics_enabled = true
    metric_name                = "${var.project_name}-waf"
  }

  tags = merge(var.tags, { Component = "waf" })
}

# -----------------------------------------------------------------------------
# API Key in SSM Parameter Store
# -----------------------------------------------------------------------------

resource "random_password" "api_key" {
  length  = 32
  special = false
}

resource "aws_ssm_parameter" "api_keys" {
  name        = "/${var.project_name}/${var.environment}/api-keys"
  description = "Comma-separated valid API keys for RUM pipeline"
  type        = "SecureString"
  value       = random_password.api_key.result

  lifecycle {
    ignore_changes = [value]
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda Authorizer
# -----------------------------------------------------------------------------

data "archive_file" "authorizer" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  excludes    = ["test_handler.py", "__pycache__", ".pytest_cache"]
  output_path = "${path.module}/files/authorizer.zip"
}

resource "aws_iam_role" "authorizer_lambda" {
  name = "${var.project_name}-authorizer-lambda-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "authorizer_lambda_logs" {
  role       = aws_iam_role.authorizer_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "authorizer_ssm" {
  name = "${var.project_name}-authorizer-ssm-access"
  role = aws_iam_role.authorizer_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["ssm:GetParameter"]
      Resource = aws_ssm_parameter.api_keys.arn
    }]
  })
}

resource "aws_lambda_function" "authorizer" {
  function_name    = "${var.project_name}-authorizer"
  role             = aws_iam_role.authorizer_lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 10
  memory_size      = 128
  filename         = data.archive_file.authorizer.output_path
  source_code_hash = data.archive_file.authorizer.output_base64sha256

  environment {
    variables = {
      SSM_PARAMETER_NAME = aws_ssm_parameter.api_keys.name
    }
  }

  tags = merge(var.tags, { Component = "authorizer" })
}

resource "aws_cloudwatch_log_group" "authorizer_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.authorizer.function_name}"
  retention_in_days = 14
  tags              = var.tags
}
