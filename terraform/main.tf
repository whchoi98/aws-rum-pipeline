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
  enable_auth              = true
  authorizer_invoke_arn    = module.security.authorizer_invoke_arn
  authorizer_function_name = module.security.authorizer_function_name
  waf_acl_arn              = module.security.waf_acl_arn
  tags                     = { Component = "ingestion" }
}

# -----------------------------------------------------------------------------
# Monitoring — CloudWatch Dashboard
# -----------------------------------------------------------------------------

module "monitoring" {
  source       = "./modules/monitoring"
  project_name = var.project_name
  region       = var.aws_region
  api_id       = module.api_gateway.api_id
  tags         = { Component = "monitoring" }
}

# -----------------------------------------------------------------------------
# Visualization — Amazon Managed Grafana + Athena
# -----------------------------------------------------------------------------

module "grafana" {
  source             = "./modules/grafana"
  project_name       = var.project_name
  account_id         = data.aws_caller_identity.current.account_id
  region             = var.aws_region
  s3_bucket_arn      = module.s3_data_lake.bucket_arn
  s3_bucket_name     = module.s3_data_lake.bucket_id
  glue_database_name = module.glue_catalog.database_name
  tags               = { Component = "visualization" }
}

# -----------------------------------------------------------------------------
# Partition Repair — Glue 파티션 자동 등록 (15분 간격)
# -----------------------------------------------------------------------------

module "partition_repair" {
  source             = "./modules/partition-repair"
  project_name       = var.project_name
  glue_database_name = module.glue_catalog.database_name
  glue_table_name    = module.glue_catalog.rum_events_table_name
  athena_workgroup   = module.grafana.athena_workgroup
  s3_bucket_arn      = module.s3_data_lake.bucket_arn
  lambda_source_dir  = "${path.module}/../lambda/partition-repair"
  tags               = { Component = "partition-repair" }
}

# -----------------------------------------------------------------------------
# Athena Query Lambda — AgentCore RUM 분석 에이전트용
# -----------------------------------------------------------------------------

module "athena_query" {
  source             = "./modules/athena-query"
  project_name       = var.project_name
  glue_database_name = module.glue_catalog.database_name
  athena_workgroup   = module.grafana.athena_workgroup
  s3_bucket_arn      = module.s3_data_lake.bucket_arn
  lambda_source_dir  = "${path.module}/../lambda/athena-query"
  tags               = { Component = "agentcore" }
}

# -----------------------------------------------------------------------------
# Auth — Cognito User Pool + SSO + Lambda@Edge
# TODO: auth 모듈은 provider 충돌 해결 후 활성화 (us-east-1 required)
# -----------------------------------------------------------------------------

# module "auth" {
#   source            = "./modules/auth"
#   project_name      = var.project_name
#   cloudfront_domain = module.agent_ui.cloudfront_domain
#   sso_metadata_url  = var.sso_metadata_url
#   lambda_source_dir = "${path.module}/../lambda/edge-auth"
#   tags              = { Component = "auth" }
#
#   providers = {
#     aws.us_east_1 = aws.us_east_1
#   }
# }

# -----------------------------------------------------------------------------
# Agent UI — CloudFront + ALB + EC2 (Next.js)
# -----------------------------------------------------------------------------

module "agent_ui" {
  source                  = "./modules/agent-ui"
  project_name            = var.project_name
  vpc_id                  = var.vpc_id
  public_subnet_ids       = var.public_subnet_ids
  instance_type           = "t4g.large"
  agentcore_endpoint_arn  = var.agentcore_endpoint_arn
  edge_auth_qualified_arn = "" # auth 모듈 미배포 시 빈 문자열
  tags                    = { Component = "agent-ui" }
}

# -----------------------------------------------------------------------------
# Session Replay — OpenReplay (CloudFront + ALB + EC2 + RDS + ElastiCache + S3)
# -----------------------------------------------------------------------------

module "openreplay" {
  count  = var.enable_openreplay ? 1 : 0
  source = "./modules/openreplay"

  project_name            = var.project_name
  environment             = var.environment
  vpc_id                  = var.vpc_id
  public_subnet_ids       = var.public_subnet_ids
  private_subnet_ids      = var.private_subnet_ids
  instance_type           = "m7g.xlarge"
  edge_auth_qualified_arn = "" # auth 모듈 미배포 시 빈 문자열
  tags                    = { Component = "session-replay" }
}
