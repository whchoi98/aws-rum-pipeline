# terraform/main.tf

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Layer 4: Storage — S3 Data Lake
# -----------------------------------------------------------------------------

module "s3_data_lake" {
  source       = "./modules/s3-data-lake"
  project_name = var.project_name
  account_id   = data.aws_caller_identity.current.account_id
  tags         = { Component = "storage" }
}

# -----------------------------------------------------------------------------
# Glue Data Catalog
# -----------------------------------------------------------------------------

module "glue_catalog" {
  source         = "./modules/glue-catalog"
  project_name   = var.project_name
  s3_bucket_name = module.s3_data_lake.bucket_id
  tags           = { Component = "catalog" }
}

# -----------------------------------------------------------------------------
# Layer 3: Stream Processing — Firehose + Lambda Transform
# -----------------------------------------------------------------------------

module "firehose" {
  source             = "./modules/firehose"
  project_name       = var.project_name
  s3_bucket_arn      = module.s3_data_lake.bucket_arn
  glue_database_name = module.glue_catalog.database_name
  glue_table_name    = module.glue_catalog.rum_events_table_name
  region             = var.aws_region
  account_id         = data.aws_caller_identity.current.account_id
  lambda_source_dir  = "${path.module}/../lambda/transform"
  tags               = { Component = "stream-processing" }
}

# -----------------------------------------------------------------------------
# Security — WAF + Lambda Authorizer
# -----------------------------------------------------------------------------

module "security" {
  source            = "./modules/security"
  project_name      = var.project_name
  environment       = var.environment
  lambda_source_dir = "${path.module}/../lambda/authorizer"
  tags              = { Component = "security" }
}

# -----------------------------------------------------------------------------
# Layer 2: Ingestion — API Gateway + Lambda Forwarder
# -----------------------------------------------------------------------------

module "api_gateway" {
  source                   = "./modules/api-gateway"
  project_name             = var.project_name
  firehose_stream_name     = module.firehose.delivery_stream_name
  firehose_stream_arn      = module.firehose.delivery_stream_arn
  lambda_source_dir        = "${path.module}/../lambda/ingest"
  allowed_origins          = var.allowed_origins
  authorizer_invoke_arn    = module.security.authorizer_invoke_arn
  authorizer_function_name = module.security.authorizer_function_name
  waf_acl_arn              = module.security.waf_acl_arn
  tags                     = { Component = "ingestion" }
}
