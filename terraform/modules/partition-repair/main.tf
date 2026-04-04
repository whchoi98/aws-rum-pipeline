# terraform/modules/partition-repair/main.tf

# -----------------------------------------------------------------------------
# Lambda — MSCK REPAIR TABLE
# -----------------------------------------------------------------------------

data "archive_file" "partition_repair" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  excludes    = ["__pycache__", ".pytest_cache"]
  output_path = "${path.module}/files/partition-repair.zip"
}

resource "aws_iam_role" "partition_repair" {
  name = "${var.project_name}-partition-repair-role"
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

resource "aws_iam_role_policy_attachment" "partition_repair_logs" {
  role       = aws_iam_role.partition_repair.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy" "partition_repair_athena" {
  name = "${var.project_name}-partition-repair-athena"
  role = aws_iam_role.partition_repair.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetTable",
          "glue:GetPartitions",
          "glue:BatchCreatePartition",
          "glue:CreatePartition"
        ]
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

resource "aws_lambda_function" "partition_repair" {
  function_name    = "${var.project_name}-partition-repair"
  role             = aws_iam_role.partition_repair.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 120
  memory_size      = 128
  filename         = data.archive_file.partition_repair.output_path
  source_code_hash = data.archive_file.partition_repair.output_base64sha256

  environment {
    variables = {
      GLUE_DATABASE    = var.glue_database_name
      GLUE_TABLE       = var.glue_table_name
      ATHENA_WORKGROUP = var.athena_workgroup
    }
  }

  tags = merge(var.tags, { Component = "partition-repair" })
}

resource "aws_cloudwatch_log_group" "partition_repair" {
  name              = "/aws/lambda/${aws_lambda_function.partition_repair.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

# -----------------------------------------------------------------------------
# EventBridge — 15분마다 실행
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "partition_repair" {
  name                = "${var.project_name}-partition-repair"
  description         = "Trigger MSCK REPAIR TABLE every 15 minutes"
  schedule_expression = var.schedule
  tags                = var.tags
}

resource "aws_cloudwatch_event_target" "partition_repair" {
  rule      = aws_cloudwatch_event_rule.partition_repair.name
  target_id = "partition-repair-lambda"
  arn       = aws_lambda_function.partition_repair.arn
}

resource "aws_lambda_permission" "eventbridge" {
  statement_id  = "AllowEventBridgeInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.partition_repair.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.partition_repair.arn
}
