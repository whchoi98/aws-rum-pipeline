data "archive_file" "athena_query" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  excludes    = ["__pycache__"]
  output_path = "${path.module}/files/athena-query.zip"
}

resource "aws_iam_role" "athena_query" {
  name = "${var.project_name}-athena-query-role"
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

resource "aws_iam_role_policy_attachment" "athena_query_logs" {
  role       = aws_iam_role.athena_query.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "athena_query" {
  name = "${var.project_name}-athena-query-policy"
  role = aws_iam_role.athena_query.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = ["athena:StartQueryExecution", "athena:GetQueryExecution", "athena:GetQueryResults", "athena:StopQueryExecution"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["glue:GetTable", "glue:GetDatabase", "glue:GetPartitions"]
        Resource = "*"
      },
      {
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:ListBucket", "s3:GetBucketLocation"]
        Resource = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"]
      }
    ]
  })
}

resource "aws_lambda_function" "athena_query" {
  function_name    = "${var.project_name}-athena-query"
  role             = aws_iam_role.athena_query.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.athena_query.output_path
  source_code_hash = data.archive_file.athena_query.output_base64sha256

  environment {
    variables = {
      GLUE_DATABASE    = var.glue_database_name
      ATHENA_WORKGROUP = var.athena_workgroup
    }
  }
  tags = merge(var.tags, { Component = "athena-query" })
}

resource "aws_cloudwatch_log_group" "athena_query" {
  name              = "/aws/lambda/${aws_lambda_function.athena_query.function_name}"
  retention_in_days = 14
  tags              = var.tags
}
