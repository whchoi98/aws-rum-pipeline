# terraform/modules/auth/main.tf
# Cognito User Pool + SSO IdP + Lambda@Edge 인증

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  cognito_domain = var.cognito_domain_prefix != "" ? var.cognito_domain_prefix : var.project_name
  callback_url   = "https://${var.cloudfront_domain}/auth/callback"
  logout_url     = "https://${var.cloudfront_domain}/"
}

# ─── Cognito User Pool ───

resource "aws_cognito_user_pool" "agent_users" {
  name = "${var.project_name}-agent-users"

  # 자체 가입 비활성화 (SSO만 허용)
  admin_create_user_config {
    allow_admin_create_user_only = true
  }

  # 이메일 설정
  auto_verified_attributes = ["email"]

  schema {
    name                = "email"
    attribute_data_type = "String"
    required            = true
    mutable             = true
    string_attribute_constraints {
      min_length = 1
      max_length = 256
    }
  }

  tags = var.tags
}

# ─── Cognito Hosted UI 도메인 ───

resource "aws_cognito_user_pool_domain" "main" {
  domain       = local.cognito_domain
  user_pool_id = aws_cognito_user_pool.agent_users.id
}

# ─── App Client (Authorization Code + PKCE) ───

resource "aws_cognito_user_pool_client" "agent_app" {
  name         = "${var.project_name}-agent-app"
  user_pool_id = aws_cognito_user_pool.agent_users.id

  # PKCE 활성화, client secret 불필요
  generate_secret = false

  allowed_oauth_flows                  = ["code"]
  allowed_oauth_flows_user_pool_client = true
  allowed_oauth_scopes                 = ["openid", "email", "profile"]
  supported_identity_providers         = var.sso_metadata_url != "" ? [var.sso_provider_name] : ["COGNITO"]

  callback_urls = [local.callback_url]
  logout_urls   = [local.logout_url]

  # 토큰 유효 시간
  id_token_validity      = 1  # 시간
  access_token_validity  = 1  # 시간
  refresh_token_validity = 30 # 일

  token_validity_units {
    id_token      = "hours"
    access_token  = "hours"
    refresh_token = "days"
  }
}

# ─── SSO Identity Provider (조건부) ───

resource "aws_cognito_identity_provider" "sso" {
  count = var.sso_metadata_url != "" ? 1 : 0

  user_pool_id  = aws_cognito_user_pool.agent_users.id
  provider_name = var.sso_provider_name
  provider_type = "SAML"

  provider_details = {
    MetadataURL = var.sso_metadata_url
    SLOEnabled  = "true"
    IDPSignout  = "true"
  }

  attribute_mapping = {
    email = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/emailaddress"
    name  = "http://schemas.xmlsoap.org/ws/2005/05/identity/claims/name"
  }
}

# ─── Lambda@Edge IAM Role ───

resource "aws_iam_role" "edge_auth" {
  name = "${var.project_name}-edge-auth"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = [
          "lambda.amazonaws.com",
          "edgelambda.amazonaws.com"
        ]
      }
      Action = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "edge_auth_basic" {
  role       = aws_iam_role.edge_auth.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# ─── Lambda@Edge 함수 (us-east-1) ───

# Lambda@Edge는 us-east-1에 배포해야 함
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

# config.json 생성 후 소스와 함께 패키징
resource "local_file" "edge_auth_config" {
  filename = "${var.lambda_source_dir}/config.json"
  content = jsonencode({
    region           = data.aws_region.current.name
    userPoolId       = aws_cognito_user_pool.agent_users.id
    clientId         = aws_cognito_user_pool_client.agent_app.id
    cognitoDomain    = "${local.cognito_domain}.auth.${data.aws_region.current.name}.amazoncognito.com"
    identityProvider = var.sso_metadata_url != "" ? var.sso_provider_name : ""
  })
}

data "archive_file" "edge_auth" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  output_path = "${path.module}/edge-auth.zip"

  depends_on = [local_file.edge_auth_config]
}

resource "aws_lambda_function" "edge_auth" {
  provider = aws.us_east_1

  function_name = "${var.project_name}-edge-auth"
  role          = aws_iam_role.edge_auth.arn
  handler       = "index.handler"
  runtime       = "nodejs20.x"
  publish       = true # Lambda@Edge는 버전 게시 필수

  filename         = data.archive_file.edge_auth.output_path
  source_code_hash = data.archive_file.edge_auth.output_base64sha256

  memory_size = 128
  timeout     = 5 # Lambda@Edge viewer-request 최대 5초

  tags = var.tags
}

resource "aws_cloudwatch_log_group" "edge_auth" {
  name              = "/aws/lambda/us-east-1.${var.project_name}-edge-auth"
  retention_in_days = 14

  tags = var.tags
}
