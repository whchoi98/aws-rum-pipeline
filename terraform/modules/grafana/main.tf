# terraform/modules/grafana/main.tf

# -----------------------------------------------------------------------------
# IAM Role — Grafana → Athena / S3 / Glue
# -----------------------------------------------------------------------------

resource "aws_iam_role" "grafana" {
  name = "${var.project_name}-grafana-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Action    = "sts:AssumeRole"
      Principal = { Service = "grafana.amazonaws.com" }
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "grafana_athena" {
  name = "${var.project_name}-grafana-athena-policy"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaAccess"
        Effect = "Allow"
        Action = [
          "athena:GetDatabase",
          "athena:GetDataCatalog",
          "athena:GetTableMetadata",
          "athena:ListDatabases",
          "athena:ListDataCatalogs",
          "athena:ListTableMetadata",
          "athena:StartQueryExecution",
          "athena:StopQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:GetWorkGroup",
          "athena:ListWorkGroups"
        ]
        Resource = "*"
      },
      {
        Sid    = "S3DataLakeAccess"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:PutObject"
        ]
        Resource = [
          var.s3_bucket_arn,
          "${var.s3_bucket_arn}/*"
        ]
      },
      {
        Sid    = "GlueAccess"
        Effect = "Allow"
        Action = [
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetPartitions"
        ]
        Resource = [
          "arn:aws:glue:${var.region}:${var.account_id}:catalog",
          "arn:aws:glue:${var.region}:${var.account_id}:database/${var.glue_database_name}",
          "arn:aws:glue:${var.region}:${var.account_id}:table/${var.glue_database_name}/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Amazon Managed Grafana Workspace
# -----------------------------------------------------------------------------

resource "aws_grafana_workspace" "rum" {
  name                     = "${var.project_name}-grafana"
  description              = "RUM pipeline observability — Core Web Vitals, Errors, Traffic"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn

  data_sources              = ["ATHENA"]
  notification_destinations = []

  tags = var.tags
}

# -----------------------------------------------------------------------------
# Athena Workgroup
# -----------------------------------------------------------------------------

resource "aws_athena_workgroup" "rum" {
  name        = "${var.project_name}-athena"
  description = "Athena workgroup for Grafana RUM dashboard queries"

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = true

    result_configuration {
      output_location = "s3://${var.s3_bucket_name}/athena-results/"
    }

    bytes_scanned_cutoff_per_query = 107374182400 # 100 GB scan limit per query
  }

  tags = var.tags
}
