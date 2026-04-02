# terraform/modules/api-gateway/main.tf

# -----------------------------------------------------------------------------
# Ingest Lambda
# -----------------------------------------------------------------------------

data "archive_file" "ingest" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  excludes    = ["test_handler.py", "__pycache__", ".pytest_cache"]
  output_path = "${path.module}/files/ingest.zip"
}

resource "aws_iam_role" "ingest_lambda" {
  name = "${var.project_name}-ingest-lambda-role"
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

resource "aws_iam_role_policy_attachment" "ingest_lambda_logs" {
  role       = aws_iam_role.ingest_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "ingest_lambda_firehose" {
  name = "${var.project_name}-ingest-firehose-access"
  role = aws_iam_role.ingest_lambda.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["firehose:PutRecord", "firehose:PutRecordBatch"]
      Resource = var.firehose_stream_arn
    }]
  })
}

resource "aws_lambda_function" "ingest" {
  function_name    = "${var.project_name}-ingest"
  role             = aws_iam_role.ingest_lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 30
  memory_size      = 128
  filename         = data.archive_file.ingest.output_path
  source_code_hash = data.archive_file.ingest.output_base64sha256

  environment {
    variables = {
      FIREHOSE_STREAM_NAME = var.firehose_stream_name
    }
  }

  tags = merge(var.tags, { Component = "ingest" })
}

resource "aws_cloudwatch_log_group" "ingest_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.ingest.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

# -----------------------------------------------------------------------------
# HTTP API Gateway
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_api" "rum" {
  name          = "${var.project_name}-api"
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = var.allowed_origins
    allow_methods = ["POST", "OPTIONS"]
    allow_headers = ["Content-Type", "x-api-key"]
    max_age       = 86400
  }

  tags = merge(var.tags, { Component = "api-gateway" })
}

resource "aws_apigatewayv2_stage" "default" {
  api_id      = aws_apigatewayv2_api.rum.id
  name        = "$default"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 1000
    throttling_rate_limit  = 500
  }

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Lambda Authorizer (conditional)
# -----------------------------------------------------------------------------

resource "aws_apigatewayv2_authorizer" "api_key" {
  count = var.enable_auth ? 1 : 0

  api_id                            = aws_apigatewayv2_api.rum.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = var.authorizer_invoke_arn
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true
  authorizer_result_ttl_in_seconds  = 300
  identity_sources                  = ["$request.header.x-api-key"]
  name                              = "${var.project_name}-api-key-authorizer"
}

# NOTE: WAF WebACL cannot be associated directly with HTTP APIs (only REST APIs,
# ALB, CloudFront). WAF association will be added when CloudFront is introduced.

# -----------------------------------------------------------------------------
# Authorizer Lambda Permission (conditional)
# -----------------------------------------------------------------------------

resource "aws_lambda_permission" "authorizer_apigw" {
  count = var.enable_auth ? 1 : 0

  statement_id  = "AllowAPIGatewayInvokeAuthorizer"
  action        = "lambda:InvokeFunction"
  function_name = var.authorizer_function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rum.execution_arn}/*/*"
}

resource "aws_apigatewayv2_integration" "ingest_lambda" {
  api_id                 = aws_apigatewayv2_api.rum.id
  integration_type       = "AWS_PROXY"
  integration_uri        = aws_lambda_function.ingest.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_route" "post_events" {
  api_id    = aws_apigatewayv2_api.rum.id
  route_key = "POST /v1/events"
  target    = "integrations/${aws_apigatewayv2_integration.ingest_lambda.id}"

  authorization_type = var.enable_auth ? "CUSTOM" : "NONE"
  authorizer_id      = var.enable_auth ? aws_apigatewayv2_authorizer.api_key[0].id : null
}

resource "aws_apigatewayv2_route" "post_beacon" {
  api_id    = aws_apigatewayv2_api.rum.id
  route_key = "POST /v1/events/beacon"
  target    = "integrations/${aws_apigatewayv2_integration.ingest_lambda.id}"

  authorization_type = var.enable_auth ? "CUSTOM" : "NONE"
  authorizer_id      = var.enable_auth ? aws_apigatewayv2_authorizer.api_key[0].id : null
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rum.execution_arn}/*/*"
}
