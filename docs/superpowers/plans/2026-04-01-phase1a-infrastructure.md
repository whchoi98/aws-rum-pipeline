# Phase 1a — RUM Pipeline Infrastructure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy the serverless ingestion pipeline that receives RUM events via HTTP, transforms them, and stores them as Parquet in S3 — ready for SDK integration in Phase 1b.

**Architecture:** HTTP API Gateway receives batched events from SDKs, forwards them via a thin Lambda forwarder to Kinesis Data Firehose. Firehose invokes a transform Lambda (schema validation, PII stripping, partition key extraction), converts to Parquet via Glue schema, and writes to S3 with dynamic partitioning (`platform/year/month/day/hour`). Glue Data Catalog tables enable Athena queries.

**Tech Stack:** Terraform (>= 1.0), AWS Provider (>= 5.0), Python 3.12 (Lambda), pytest (Lambda tests)

**Spec reference:** `docs/superpowers/specs/2026-04-01-aws-rum-pipeline-design.md`

**Spec deviation — API Gateway → Firehose integration:**
The spec says "HTTP API → Firehose Service Integration (Lambda-free)." However, HTTP API only supports direct service integration with SQS, Kinesis Data Streams, EventBridge, Step Functions, and AppConfig — **not** Firehose. REST API supports Firehose, but costs 3.5x more ($3.50/M vs $1.00/M). This plan uses **HTTP API + thin Lambda forwarder** (~$3/month extra) as the best cost/simplicity tradeoff.

**Deferred to Phase 1a.5 (security hardening):**
- Lambda Authorizer for API key validation + DynamoDB rate limiting
- WAF (bot detection, IP-based rate rules)
- `GET /v1/config` endpoint (SDK remote configuration)
- `GET /v1/health` endpoint
- Origin/Referer header validation

---

## File Structure

```
rum/
├── terraform/
│   ├── providers.tf                          # AWS provider, required_version
│   ├── backend.tf                            # S3 backend for state
│   ├── variables.tf                          # Root input variables
│   ├── outputs.tf                            # Root outputs (API URL, bucket name, etc.)
│   ├── main.tf                               # Module instantiations
│   └── modules/
│       ├── s3-data-lake/
│       │   ├── main.tf                       # S3 bucket, lifecycle, encryption
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── glue-catalog/
│       │   ├── main.tf                       # Glue DB + rum_events table
│       │   ├── variables.tf
│       │   └── outputs.tf
│       ├── firehose/
│       │   ├── main.tf                       # Firehose stream, transform Lambda deploy, IAM
│       │   ├── variables.tf
│       │   └── outputs.tf
│       └── api-gateway/
│           ├── main.tf                       # HTTP API, routes, ingest Lambda deploy, IAM
│           ├── variables.tf
│           └── outputs.tf
├── lambda/
│   ├── transform/
│   │   ├── handler.py                        # Firehose transform: validate, enrich, partition keys
│   │   └── test_handler.py                   # Unit tests
│   └── ingest/
│       ├── handler.py                        # Thin forwarder: HTTP → Firehose PutRecordBatch
│       └── test_handler.py                   # Unit tests
└── scripts/
    └── test-ingestion.sh                     # End-to-end curl test
```

---

## Task 1: Project Scaffold

**Files:**
- Create: `rum/terraform/providers.tf`
- Create: `rum/terraform/backend.tf`
- Create: `rum/terraform/variables.tf`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p rum/terraform/modules/{s3-data-lake,glue-catalog,firehose,api-gateway}
mkdir -p rum/lambda/{transform,ingest}
mkdir -p rum/scripts
```

- [ ] **Step 2: Write providers.tf**

```hcl
# rum/terraform/providers.tf
terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = ">= 2.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
  default_tags {
    tags = {
      Environment = var.environment
      Project     = var.project_name
      ManagedBy   = "terraform"
    }
  }
}
```

- [ ] **Step 3: Write backend.tf**

```hcl
# rum/terraform/backend.tf
terraform {
  backend "s3" {
    bucket         = "rum-pipeline-terraform-state"
    key            = "rum-pipeline/terraform.tfstate"
    region         = "ap-northeast-2"
    dynamodb_table = "terraform-state-lock"
    encrypt        = true
  }
}
```

- [ ] **Step 4: Write variables.tf**

```hcl
# rum/terraform/variables.tf
variable "aws_region" {
  description = "AWS region for RUM pipeline"
  type        = string
  default     = "ap-northeast-2"
}

variable "environment" {
  description = "Environment name (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
  default     = "rum-pipeline"
}

variable "allowed_origins" {
  description = "CORS allowed origins for the API"
  type        = list(string)
  default     = ["*"]
}
```

- [ ] **Step 5: Run terraform init and validate**

```bash
cd rum/terraform && terraform init -backend=false && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 6: Commit**

```bash
git add rum/terraform/providers.tf rum/terraform/backend.tf rum/terraform/variables.tf
git commit -m "feat(rum): scaffold Terraform project with providers and variables"
```

---

## Task 2: S3 Data Lake Module

**Files:**
- Create: `rum/terraform/modules/s3-data-lake/main.tf`
- Create: `rum/terraform/modules/s3-data-lake/variables.tf`
- Create: `rum/terraform/modules/s3-data-lake/outputs.tf`

- [ ] **Step 1: Write variables.tf**

```hcl
# rum/terraform/modules/s3-data-lake/variables.tf
variable "project_name" {
  description = "Project name for bucket naming"
  type        = string
}

variable "account_id" {
  description = "AWS account ID for globally unique bucket name"
  type        = string
}

variable "raw_expiration_days" {
  description = "Days before raw data expires"
  type        = number
  default     = 90
}

variable "error_expiration_days" {
  description = "Days before error records expire"
  type        = number
  default     = 30
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Write main.tf**

```hcl
# rum/terraform/modules/s3-data-lake/main.tf
resource "aws_s3_bucket" "data_lake" {
  bucket = "${var.project_name}-data-lake-${var.account_id}"
  tags   = merge(var.tags, { Component = "storage" })
}

resource "aws_s3_bucket_versioning" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "data_lake" {
  bucket                  = aws_s3_bucket.data_lake.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "data_lake" {
  bucket = aws_s3_bucket.data_lake.id

  rule {
    id     = "raw-expiration"
    status = "Enabled"
    filter {
      prefix = "raw/"
    }
    expiration {
      days = var.raw_expiration_days
    }
  }

  rule {
    id     = "aggregated-tiering"
    status = "Enabled"
    filter {
      prefix = "aggregated/"
    }
    transition {
      days          = 90
      storage_class = "STANDARD_IA"
    }
    transition {
      days          = 365
      storage_class = "GLACIER"
    }
  }

  rule {
    id     = "errors-expiration"
    status = "Enabled"
    filter {
      prefix = "errors/"
    }
    expiration {
      days = var.error_expiration_days
    }
  }
}
```

- [ ] **Step 3: Write outputs.tf**

```hcl
# rum/terraform/modules/s3-data-lake/outputs.tf
output "bucket_id" {
  description = "S3 bucket name"
  value       = aws_s3_bucket.data_lake.id
}

output "bucket_arn" {
  description = "S3 bucket ARN"
  value       = aws_s3_bucket.data_lake.arn
}
```

- [ ] **Step 4: Validate module**

```bash
cd rum/terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add rum/terraform/modules/s3-data-lake/
git commit -m "feat(rum): add S3 data lake module with lifecycle policies"
```

---

## Task 3: Glue Catalog Module

**Files:**
- Create: `rum/terraform/modules/glue-catalog/main.tf`
- Create: `rum/terraform/modules/glue-catalog/variables.tf`
- Create: `rum/terraform/modules/glue-catalog/outputs.tf`

- [ ] **Step 1: Write variables.tf**

```hcl
# rum/terraform/modules/glue-catalog/variables.tf
variable "project_name" {
  description = "Project name for database naming"
  type        = string
}

variable "s3_bucket_name" {
  description = "S3 data lake bucket name for table locations"
  type        = string
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Write main.tf**

The Glue table schema defines columns that go INTO the Parquet file. Partition keys (`platform`, `year`, `month`, `day`, `hour`) are separate — their values come from the S3 prefix path, not from Parquet columns. `payload` and `context` are stored as JSON strings for schema flexibility.

```hcl
# rum/terraform/modules/glue-catalog/main.tf
resource "aws_glue_catalog_database" "rum" {
  name        = "${replace(var.project_name, "-", "_")}_db"
  description = "RUM pipeline data catalog"
}

resource "aws_glue_catalog_table" "rum_events" {
  name          = "rum_events"
  database_name = aws_glue_catalog_database.rum.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"      = "parquet"
    "parquet.compression" = "SNAPPY"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/raw/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "session_id"
      type = "string"
    }
    columns {
      name = "user_id"
      type = "string"
    }
    columns {
      name = "device_id"
      type = "string"
    }
    columns {
      name = "timestamp"
      type = "bigint"
    }
    columns {
      name = "app_version"
      type = "string"
    }
    columns {
      name = "event_type"
      type = "string"
    }
    columns {
      name = "event_name"
      type = "string"
    }
    columns {
      name = "payload"
      type = "string"
    }
    columns {
      name = "context"
      type = "string"
    }
  }

  partition_keys {
    name = "platform"
    type = "string"
  }
  partition_keys {
    name = "year"
    type = "string"
  }
  partition_keys {
    name = "month"
    type = "string"
  }
  partition_keys {
    name = "day"
    type = "string"
  }
  partition_keys {
    name = "hour"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "rum_hourly_metrics" {
  name          = "rum_hourly_metrics"
  database_name = aws_glue_catalog_database.rum.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"      = "parquet"
    "parquet.compression" = "SNAPPY"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/aggregated/hourly/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "metric_name"
      type = "string"
    }
    columns {
      name = "platform"
      type = "string"
    }
    columns {
      name = "period_start"
      type = "bigint"
    }
    columns {
      name = "p50"
      type = "double"
    }
    columns {
      name = "p75"
      type = "double"
    }
    columns {
      name = "p95"
      type = "double"
    }
    columns {
      name = "p99"
      type = "double"
    }
    columns {
      name = "count"
      type = "bigint"
    }
    columns {
      name = "error_count"
      type = "bigint"
    }
    columns {
      name = "active_users"
      type = "bigint"
    }
  }

  partition_keys {
    name = "metric"
    type = "string"
  }
  partition_keys {
    name = "dt"
    type = "string"
  }
}

resource "aws_glue_catalog_table" "rum_daily_summary" {
  name          = "rum_daily_summary"
  database_name = aws_glue_catalog_database.rum.name
  table_type    = "EXTERNAL_TABLE"

  parameters = {
    "classification"      = "parquet"
    "parquet.compression" = "SNAPPY"
  }

  storage_descriptor {
    location      = "s3://${var.s3_bucket_name}/aggregated/daily/"
    input_format  = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetInputFormat"
    output_format = "org.apache.hadoop.hive.ql.io.parquet.MapredParquetOutputFormat"

    ser_de_info {
      serialization_library = "org.apache.hadoop.hive.ql.io.parquet.serde.ParquetHiveSerDe"
      parameters = {
        "serialization.format" = "1"
      }
    }

    columns {
      name = "date"
      type = "string"
    }
    columns {
      name = "platform"
      type = "string"
    }
    columns {
      name = "dau"
      type = "bigint"
    }
    columns {
      name = "sessions"
      type = "bigint"
    }
    columns {
      name = "avg_session_duration_sec"
      type = "double"
    }
    columns {
      name = "new_users"
      type = "bigint"
    }
    columns {
      name = "returning_users"
      type = "bigint"
    }
    columns {
      name = "top_pages"
      type = "string"
    }
    columns {
      name = "top_errors"
      type = "string"
    }
    columns {
      name = "device_distribution"
      type = "string"
    }
    columns {
      name = "geo_distribution"
      type = "string"
    }
  }

  partition_keys {
    name = "dt"
    type = "string"
  }
}
```

- [ ] **Step 3: Write outputs.tf**

```hcl
# rum/terraform/modules/glue-catalog/outputs.tf
output "database_name" {
  description = "Glue catalog database name"
  value       = aws_glue_catalog_database.rum.name
}

output "rum_events_table_name" {
  description = "Glue table name for raw RUM events"
  value       = aws_glue_catalog_table.rum_events.name
}
```

- [ ] **Step 4: Validate module**

```bash
cd rum/terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add rum/terraform/modules/glue-catalog/
git commit -m "feat(rum): add Glue catalog module with rum_events, hourly, daily tables"
```

---

## Task 4: Lambda Transform Function

**Files:**
- Create: `rum/lambda/transform/test_handler.py`
- Create: `rum/lambda/transform/handler.py`

- [ ] **Step 1: Write the failing tests**

```python
# rum/lambda/transform/test_handler.py
import json
import base64
import pytest


def _make_record(data, record_id="rec-001"):
    """Helper: wrap a dict as a Firehose input record."""
    encoded = base64.b64encode(json.dumps(data).encode("utf-8")).decode("utf-8")
    return {"recordId": record_id, "data": encoded}


def _decode_record(record):
    """Helper: decode a Firehose output record's data field."""
    return json.loads(base64.b64decode(record["data"]).decode("utf-8"))


VALID_EVENT = {
    "session_id": "sess-abc-123",
    "user_id": "user-hash-456",
    "device_id": "dev-789",
    "timestamp": 1743465600000,  # 2025-04-01 00:00:00 UTC
    "platform": "web",
    "app_version": "2.1.0",
    "event_type": "performance",
    "event_name": "lcp",
    "payload": {"value": 2500, "rating": "good"},
    "context": {
        "url": "/products/123",
        "device": {"os": "macOS", "browser": "Chrome 120"},
    },
}


class TestSchemaValidation:
    def test_valid_event_returns_ok(self):
        from handler import handler

        event = {"records": [_make_record(VALID_EVENT)]}
        result = handler(event, None)
        assert len(result["records"]) == 1
        assert result["records"][0]["result"] == "Ok"

    def test_missing_required_field_returns_processing_failed(self):
        from handler import handler

        incomplete = {k: v for k, v in VALID_EVENT.items() if k != "session_id"}
        event = {"records": [_make_record(incomplete)]}
        result = handler(event, None)
        assert result["records"][0]["result"] == "ProcessingFailed"

    def test_invalid_json_returns_processing_failed(self):
        from handler import handler

        bad_record = {
            "recordId": "rec-bad",
            "data": base64.b64encode(b"not json").decode("utf-8"),
        }
        result = handler({"records": [bad_record]}, None)
        assert result["records"][0]["result"] == "ProcessingFailed"


class TestPartitionKeys:
    def test_partition_keys_extracted_from_timestamp(self):
        from handler import handler

        event = {"records": [_make_record(VALID_EVENT)]}
        result = handler(event, None)
        rec = result["records"][0]
        keys = rec["metadata"]["partitionKeys"]
        assert keys["platform"] == "web"
        assert keys["year"] == "2025"
        assert keys["month"] == "04"
        assert keys["day"] == "01"
        assert keys["hour"] == "00"

    def test_partition_keys_for_mobile_platform(self):
        from handler import handler

        mobile_event = {**VALID_EVENT, "platform": "ios"}
        event = {"records": [_make_record(mobile_event)]}
        result = handler(event, None)
        keys = result["records"][0]["metadata"]["partitionKeys"]
        assert keys["platform"] == "ios"


class TestPiiStripping:
    def test_ip_removed_from_root(self):
        from handler import handler

        event_with_ip = {**VALID_EVENT, "ip": "1.2.3.4"}
        event = {"records": [_make_record(event_with_ip)]}
        result = handler(event, None)
        data = _decode_record(result["records"][0])
        assert "ip" not in data

    def test_ip_removed_from_context(self):
        from handler import handler

        event_with_ip = {
            **VALID_EVENT,
            "context": {**VALID_EVENT["context"], "ip": "1.2.3.4"},
        }
        event = {"records": [_make_record(event_with_ip)]}
        result = handler(event, None)
        data = _decode_record(result["records"][0])
        assert "ip" not in data.get("context", {})


class TestBatchProcessing:
    def test_multiple_records_processed_independently(self):
        from handler import handler

        good = _make_record(VALID_EVENT, "rec-good")
        bad = _make_record({"incomplete": True}, "rec-bad")
        result = handler({"records": [good, bad]}, None)

        results_map = {r["recordId"]: r["result"] for r in result["records"]}
        assert results_map["rec-good"] == "Ok"
        assert results_map["rec-bad"] == "ProcessingFailed"
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd rum/lambda/transform && python -m pytest test_handler.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'handler'`

- [ ] **Step 3: Write handler.py implementation**

```python
# rum/lambda/transform/handler.py
"""Firehose transform Lambda: validates schema, strips PII, extracts partition keys."""

import json
import base64
from datetime import datetime, timezone

REQUIRED_FIELDS = ["session_id", "timestamp", "platform", "event_type", "event_name"]


def handler(event, context):
    output = []

    for record in event["records"]:
        record_id = record["recordId"]
        try:
            raw = base64.b64decode(record["data"]).decode("utf-8")
            data = json.loads(raw)

            # Schema validation
            missing = [f for f in REQUIRED_FIELDS if f not in data]
            if missing:
                output.append(
                    {
                        "recordId": record_id,
                        "result": "ProcessingFailed",
                        "data": record["data"],
                    }
                )
                continue

            # Extract timestamp for partitioning
            ts = data["timestamp"]
            if isinstance(ts, (int, float)):
                dt = datetime.fromtimestamp(ts / 1000, tz=timezone.utc)
            else:
                dt = datetime.fromisoformat(str(ts))

            # Strip PII — remove IP addresses
            data.pop("ip", None)
            ctx = data.get("context")
            if isinstance(ctx, dict):
                ctx.pop("ip", None)

            # Serialize payload and context to JSON strings for Parquet
            if "payload" in data and not isinstance(data["payload"], str):
                data["payload"] = json.dumps(data["payload"])
            if "context" in data and not isinstance(data["context"], str):
                data["context"] = json.dumps(data["context"])

            # Encode transformed data
            transformed = json.dumps(data) + "\n"
            encoded = base64.b64encode(transformed.encode("utf-8")).decode("utf-8")

            output.append(
                {
                    "recordId": record_id,
                    "result": "Ok",
                    "data": encoded,
                    "metadata": {
                        "partitionKeys": {
                            "platform": data["platform"],
                            "year": dt.strftime("%Y"),
                            "month": dt.strftime("%m"),
                            "day": dt.strftime("%d"),
                            "hour": dt.strftime("%H"),
                        }
                    },
                }
            )
        except (json.JSONDecodeError, KeyError, ValueError, TypeError):
            output.append(
                {
                    "recordId": record_id,
                    "result": "ProcessingFailed",
                    "data": record["data"],
                }
            )

    return {"records": output}
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd rum/lambda/transform && python -m pytest test_handler.py -v
```

Expected: All 7 tests PASS

- [ ] **Step 5: Commit**

```bash
git add rum/lambda/transform/
git commit -m "feat(rum): add Firehose transform Lambda with schema validation and PII stripping"
```

---

## Task 5: Firehose Module

**Files:**
- Create: `rum/terraform/modules/firehose/main.tf`
- Create: `rum/terraform/modules/firehose/variables.tf`
- Create: `rum/terraform/modules/firehose/outputs.tf`

- [ ] **Step 1: Write variables.tf**

```hcl
# rum/terraform/modules/firehose/variables.tf
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 data lake bucket"
  type        = string
}

variable "glue_database_name" {
  description = "Glue catalog database name"
  type        = string
}

variable "glue_table_name" {
  description = "Glue catalog table name for Parquet schema"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to the transform Lambda source directory"
  type        = string
}

variable "buffering_size_mb" {
  description = "Firehose buffer size in MB (min 64 with dynamic partitioning)"
  type        = number
  default     = 64
}

variable "buffering_interval_sec" {
  description = "Firehose buffer interval in seconds"
  type        = number
  default     = 60
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Write main.tf**

```hcl
# rum/terraform/modules/firehose/main.tf

# -----------------------------------------------------------------------------
# Transform Lambda
# -----------------------------------------------------------------------------

data "archive_file" "transform" {
  type        = "zip"
  source_dir  = var.lambda_source_dir
  excludes    = ["test_handler.py", "__pycache__", ".pytest_cache"]
  output_path = "${path.module}/files/transform.zip"
}

resource "aws_iam_role" "transform_lambda" {
  name = "${var.project_name}-transform-lambda-role"
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

resource "aws_iam_role_policy_attachment" "transform_lambda_logs" {
  role       = aws_iam_role.transform_lambda.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_lambda_function" "transform" {
  function_name    = "${var.project_name}-transform"
  role             = aws_iam_role.transform_lambda.arn
  handler          = "handler.handler"
  runtime          = "python3.12"
  timeout          = 60
  memory_size      = 256
  filename         = data.archive_file.transform.output_path
  source_code_hash = data.archive_file.transform.output_base64sha256
  tags             = merge(var.tags, { Component = "transform" })
}

resource "aws_cloudwatch_log_group" "transform_lambda" {
  name              = "/aws/lambda/${aws_lambda_function.transform.function_name}"
  retention_in_days = 14
  tags              = var.tags
}

# -----------------------------------------------------------------------------
# Firehose IAM Role
# -----------------------------------------------------------------------------

resource "aws_iam_role" "firehose" {
  name = "${var.project_name}-firehose-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action    = "sts:AssumeRole"
      Effect    = "Allow"
      Principal = { Service = "firehose.amazonaws.com" }
    }]
  })
  tags = var.tags
}

resource "aws_iam_role_policy" "firehose" {
  name = "${var.project_name}-firehose-policy"
  role = aws_iam_role.firehose.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3Access"
        Effect = "Allow"
        Action = [
          "s3:AbortMultipartUpload",
          "s3:GetBucketLocation",
          "s3:GetObject",
          "s3:ListBucket",
          "s3:ListBucketMultipartUploads",
          "s3:PutObject"
        ]
        Resource = [var.s3_bucket_arn, "${var.s3_bucket_arn}/*"]
      },
      {
        Sid    = "LambdaInvoke"
        Effect = "Allow"
        Action = ["lambda:InvokeFunction", "lambda:GetFunctionConfiguration"]
        Resource = [
          aws_lambda_function.transform.arn,
          "${aws_lambda_function.transform.arn}:*"
        ]
      },
      {
        Sid    = "GlueAccess"
        Effect = "Allow"
        Action = ["glue:GetTable", "glue:GetTableVersion", "glue:GetTableVersions"]
        Resource = [
          "arn:aws:glue:${var.region}:${var.account_id}:catalog",
          "arn:aws:glue:${var.region}:${var.account_id}:database/${var.glue_database_name}",
          "arn:aws:glue:${var.region}:${var.account_id}:table/${var.glue_database_name}/${var.glue_table_name}"
        ]
      },
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:PutLogEvents", "logs:CreateLogStream"]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Kinesis Data Firehose Delivery Stream
# -----------------------------------------------------------------------------

resource "aws_kinesis_firehose_delivery_stream" "rum_events" {
  name        = "${var.project_name}-events"
  destination = "extended_s3"
  tags        = merge(var.tags, { Component = "firehose" })

  extended_s3_configuration {
    role_arn            = aws_iam_role.firehose.arn
    bucket_arn          = var.s3_bucket_arn
    buffering_size      = var.buffering_size_mb
    buffering_interval  = var.buffering_interval_sec
    prefix              = "raw/platform=!{partitionKeyFromLambda:platform}/year=!{partitionKeyFromLambda:year}/month=!{partitionKeyFromLambda:month}/day=!{partitionKeyFromLambda:day}/hour=!{partitionKeyFromLambda:hour}/"
    error_output_prefix = "errors/year=!{timestamp:yyyy}/month=!{timestamp:MM}/day=!{timestamp:dd}/hour=!{timestamp:HH}/!{firehose:error-output-type}/"

    dynamic_partitioning_configuration {
      enabled = true
    }

    processing_configuration {
      enabled = true
      processors {
        type = "Lambda"
        parameters {
          parameter_name  = "LambdaArn"
          parameter_value = "${aws_lambda_function.transform.arn}:$LATEST"
        }
        parameters {
          parameter_name  = "BufferSizeInMBs"
          parameter_value = "1"
        }
        parameters {
          parameter_name  = "BufferIntervalInSeconds"
          parameter_value = "60"
        }
      }
    }

    data_format_conversion_configuration {
      input_format_configuration {
        deserializer {
          open_x_json_ser_de {}
        }
      }
      output_format_configuration {
        serializer {
          parquet_ser_de {
            compression = "SNAPPY"
          }
        }
      }
      schema_configuration {
        database_name = var.glue_database_name
        table_name    = var.glue_table_name
        role_arn      = aws_iam_role.firehose.arn
      }
    }

    cloudwatch_logging_options {
      enabled         = true
      log_group_name  = aws_cloudwatch_log_group.firehose.name
      log_stream_name = "S3Delivery"
    }
  }
}

resource "aws_cloudwatch_log_group" "firehose" {
  name              = "/aws/firehose/${var.project_name}-events"
  retention_in_days = 14
  tags              = var.tags
}
```

- [ ] **Step 3: Write outputs.tf**

```hcl
# rum/terraform/modules/firehose/outputs.tf
output "delivery_stream_name" {
  description = "Firehose delivery stream name"
  value       = aws_kinesis_firehose_delivery_stream.rum_events.name
}

output "delivery_stream_arn" {
  description = "Firehose delivery stream ARN"
  value       = aws_kinesis_firehose_delivery_stream.rum_events.arn
}

output "transform_lambda_arn" {
  description = "Transform Lambda function ARN"
  value       = aws_lambda_function.transform.arn
}
```

- [ ] **Step 4: Validate module**

```bash
cd rum/terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add rum/terraform/modules/firehose/
git commit -m "feat(rum): add Firehose module with Lambda transform and Parquet conversion"
```

---

## Task 6: Lambda Ingest Function

**Files:**
- Create: `rum/lambda/ingest/test_handler.py`
- Create: `rum/lambda/ingest/handler.py`

- [ ] **Step 1: Write the failing tests**

```python
# rum/lambda/ingest/test_handler.py
import json
import base64
import os
from unittest.mock import patch, MagicMock
import pytest

# Set env before import
os.environ["FIREHOSE_STREAM_NAME"] = "test-stream"


class TestIngestHandler:
    @patch("handler.firehose")
    def test_batch_events_forwarded_to_firehose(self, mock_firehose):
        from handler import handler

        mock_firehose.put_record_batch.return_value = {"FailedPutCount": 0}
        events = [
            {"session_id": "s1", "event_type": "performance", "event_name": "lcp"},
            {"session_id": "s2", "event_type": "action", "event_name": "click"},
        ]
        api_event = {"body": json.dumps(events), "isBase64Encoded": False}
        result = handler(api_event, None)

        assert result["statusCode"] == 200
        body = json.loads(result["body"])
        assert body["count"] == 2
        mock_firehose.put_record_batch.assert_called_once()
        call_args = mock_firehose.put_record_batch.call_args
        assert call_args.kwargs["DeliveryStreamName"] == "test-stream"
        assert len(call_args.kwargs["Records"]) == 2

    @patch("handler.firehose")
    def test_single_event_wrapped_as_list(self, mock_firehose):
        from handler import handler

        mock_firehose.put_record_batch.return_value = {"FailedPutCount": 0}
        single = {"session_id": "s1", "event_type": "action", "event_name": "click"}
        api_event = {"body": json.dumps(single), "isBase64Encoded": False}
        result = handler(api_event, None)

        assert result["statusCode"] == 200
        assert json.loads(result["body"])["count"] == 1

    def test_invalid_json_returns_400(self):
        from handler import handler

        api_event = {"body": "not-json{", "isBase64Encoded": False}
        result = handler(api_event, None)
        assert result["statusCode"] == 400

    @patch("handler.firehose")
    def test_base64_encoded_body_decoded(self, mock_firehose):
        from handler import handler

        mock_firehose.put_record_batch.return_value = {"FailedPutCount": 0}
        events = [{"session_id": "s1", "event_type": "action", "event_name": "tap"}]
        encoded_body = base64.b64encode(json.dumps(events).encode("utf-8")).decode(
            "utf-8"
        )
        api_event = {"body": encoded_body, "isBase64Encoded": True}
        result = handler(api_event, None)

        assert result["statusCode"] == 200
        assert json.loads(result["body"])["count"] == 1

    @patch("handler.firehose")
    def test_large_batch_split_into_500_chunks(self, mock_firehose):
        from handler import handler

        mock_firehose.put_record_batch.return_value = {"FailedPutCount": 0}
        events = [{"session_id": f"s{i}", "event_type": "action", "event_name": "click"} for i in range(750)]
        api_event = {"body": json.dumps(events), "isBase64Encoded": False}
        result = handler(api_event, None)

        assert result["statusCode"] == 200
        assert mock_firehose.put_record_batch.call_count == 2
```

- [ ] **Step 2: Run tests to verify they fail**

```bash
cd rum/lambda/ingest && python -m pytest test_handler.py -v
```

Expected: FAIL — `ModuleNotFoundError: No module named 'handler'`

- [ ] **Step 3: Write handler.py implementation**

```python
# rum/lambda/ingest/handler.py
"""Thin Lambda forwarder: receives HTTP batch events, sends to Firehose."""

import json
import os
import base64
import boto3

firehose = boto3.client("firehose")
STREAM_NAME = os.environ["FIREHOSE_STREAM_NAME"]


def handler(event, context):
    body = event.get("body", "")
    if event.get("isBase64Encoded"):
        body = base64.b64decode(body).decode("utf-8")

    try:
        parsed = json.loads(body)
        events = parsed if isinstance(parsed, list) else [parsed]
    except (json.JSONDecodeError, TypeError):
        return {
            "statusCode": 400,
            "headers": {"Content-Type": "application/json"},
            "body": json.dumps({"error": "Invalid JSON"}),
        }

    records = [{"Data": (json.dumps(e) + "\n").encode("utf-8")} for e in events]

    # PutRecordBatch limit: 500 records per call
    for i in range(0, len(records), 500):
        batch = records[i : i + 500]
        firehose.put_record_batch(DeliveryStreamName=STREAM_NAME, Records=batch)

    return {
        "statusCode": 200,
        "headers": {
            "Content-Type": "application/json",
            "Access-Control-Allow-Origin": "*",
        },
        "body": json.dumps({"status": "ok", "count": len(records)}),
    }
```

- [ ] **Step 4: Run tests to verify they pass**

```bash
cd rum/lambda/ingest && python -m pytest test_handler.py -v
```

Expected: All 5 tests PASS

- [ ] **Step 5: Commit**

```bash
git add rum/lambda/ingest/
git commit -m "feat(rum): add ingest Lambda forwarder for HTTP to Firehose bridging"
```

---

## Task 7: API Gateway Module

**Files:**
- Create: `rum/terraform/modules/api-gateway/main.tf`
- Create: `rum/terraform/modules/api-gateway/variables.tf`
- Create: `rum/terraform/modules/api-gateway/outputs.tf`

- [ ] **Step 1: Write variables.tf**

```hcl
# rum/terraform/modules/api-gateway/variables.tf
variable "project_name" {
  description = "Project name for resource naming"
  type        = string
}

variable "firehose_stream_name" {
  description = "Firehose delivery stream name (passed to ingest Lambda env var)"
  type        = string
}

variable "firehose_stream_arn" {
  description = "Firehose delivery stream ARN (for Lambda IAM policy)"
  type        = string
}

variable "lambda_source_dir" {
  description = "Path to the ingest Lambda source directory"
  type        = string
}

variable "allowed_origins" {
  description = "CORS allowed origins"
  type        = list(string)
  default     = ["*"]
}

variable "tags" {
  description = "Additional tags"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Write main.tf**

```hcl
# rum/terraform/modules/api-gateway/main.tf

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
}

resource "aws_apigatewayv2_route" "post_beacon" {
  api_id    = aws_apigatewayv2_api.rum.id
  route_key = "POST /v1/events/beacon"
  target    = "integrations/${aws_apigatewayv2_integration.ingest_lambda.id}"
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.ingest.function_name
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.rum.execution_arn}/*/*"
}
```

- [ ] **Step 3: Write outputs.tf**

```hcl
# rum/terraform/modules/api-gateway/outputs.tf
output "api_endpoint" {
  description = "HTTP API invoke URL"
  value       = aws_apigatewayv2_api.rum.api_endpoint
}

output "api_id" {
  description = "HTTP API ID"
  value       = aws_apigatewayv2_api.rum.id
}

output "ingest_lambda_arn" {
  description = "Ingest Lambda function ARN"
  value       = aws_lambda_function.ingest.arn
}
```

- [ ] **Step 4: Validate module**

```bash
cd rum/terraform && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 5: Commit**

```bash
git add rum/terraform/modules/api-gateway/
git commit -m "feat(rum): add API Gateway module with HTTP API and ingest Lambda"
```

---

## Task 8: Root main.tf — Wire All Modules

**Files:**
- Create: `rum/terraform/main.tf`
- Create: `rum/terraform/outputs.tf`

- [ ] **Step 1: Write main.tf**

```hcl
# rum/terraform/main.tf

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
  source              = "./modules/firehose"
  project_name        = var.project_name
  s3_bucket_arn       = module.s3_data_lake.bucket_arn
  glue_database_name  = module.glue_catalog.database_name
  glue_table_name     = module.glue_catalog.rum_events_table_name
  region              = var.aws_region
  account_id          = data.aws_caller_identity.current.account_id
  lambda_source_dir   = "${path.module}/../lambda/transform"
  tags                = { Component = "stream-processing" }
}

# -----------------------------------------------------------------------------
# Layer 2: Ingestion — API Gateway + Lambda Forwarder
# -----------------------------------------------------------------------------

module "api_gateway" {
  source               = "./modules/api-gateway"
  project_name         = var.project_name
  firehose_stream_name = module.firehose.delivery_stream_name
  firehose_stream_arn  = module.firehose.delivery_stream_arn
  lambda_source_dir    = "${path.module}/../lambda/ingest"
  allowed_origins      = var.allowed_origins
  tags                 = { Component = "ingestion" }
}
```

- [ ] **Step 2: Write outputs.tf**

```hcl
# rum/terraform/outputs.tf
output "api_endpoint" {
  description = "RUM API endpoint URL"
  value       = module.api_gateway.api_endpoint
}

output "s3_bucket_name" {
  description = "S3 data lake bucket name"
  value       = module.s3_data_lake.bucket_id
}

output "firehose_stream_name" {
  description = "Firehose delivery stream name"
  value       = module.firehose.delivery_stream_name
}

output "glue_database_name" {
  description = "Glue catalog database name"
  value       = module.glue_catalog.database_name
}
```

- [ ] **Step 3: Run terraform init and validate**

```bash
cd rum/terraform && terraform init -backend=false && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Run terraform plan (dry run)**

```bash
cd rum/terraform && terraform plan -var="environment=dev"
```

Expected: Plan shows creation of ~20 resources:
- 1 S3 bucket + 4 config resources
- 1 Glue database + 3 Glue tables
- 1 Firehose delivery stream + IAM + Lambda + CloudWatch
- 1 HTTP API + stage + integration + 2 routes + Lambda + IAM + CloudWatch

- [ ] **Step 5: Commit**

```bash
git add rum/terraform/main.tf rum/terraform/outputs.tf
git commit -m "feat(rum): wire all modules in root main.tf with dependency chain"
```

---

## Task 9: Integration Test Script

**Files:**
- Create: `rum/scripts/test-ingestion.sh`

- [ ] **Step 1: Write test script**

```bash
#!/usr/bin/env bash
# rum/scripts/test-ingestion.sh
# End-to-end test: sends sample RUM events to the deployed API endpoint.
# Usage: ./test-ingestion.sh <api-endpoint>
# Example: ./test-ingestion.sh https://abc123.execute-api.ap-northeast-2.amazonaws.com

set -euo pipefail

API_ENDPOINT="${1:?Usage: $0 <api-endpoint>}"
EVENTS_URL="${API_ENDPOINT}/v1/events"

echo "=== RUM Pipeline Integration Test ==="
echo "Endpoint: ${EVENTS_URL}"
echo ""

# Test 1: Single performance event
echo "--- Test 1: Single performance event ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${EVENTS_URL}" \
  -H "Content-Type: application/json" \
  -d '[{
    "session_id": "test-sess-001",
    "user_id": "test-user-hash",
    "device_id": "test-dev-001",
    "timestamp": '"$(date +%s000)"',
    "platform": "web",
    "app_version": "1.0.0-test",
    "event_type": "performance",
    "event_name": "lcp",
    "payload": {"value": 2500, "rating": "good"},
    "context": {"url": "/test", "device": {"os": "macOS", "browser": "Chrome 120"}}
  }]')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)
echo "Status: ${HTTP_CODE}"
echo "Body: ${BODY}"
if [ "$HTTP_CODE" = "200" ]; then echo "PASS"; else echo "FAIL"; exit 1; fi
echo ""

# Test 2: Batch of mixed events
echo "--- Test 2: Batch of 3 mixed events ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${EVENTS_URL}" \
  -H "Content-Type: application/json" \
  -d '[
    {"session_id":"test-sess-002","user_id":"u1","device_id":"d1","timestamp":'"$(date +%s000)"',"platform":"web","app_version":"1.0.0","event_type":"navigation","event_name":"page_view","payload":{"page":"/home"},"context":{"url":"/home"}},
    {"session_id":"test-sess-002","user_id":"u1","device_id":"d1","timestamp":'"$(date +%s000)"',"platform":"web","app_version":"1.0.0","event_type":"action","event_name":"click","payload":{"target":"#buy-btn"},"context":{"url":"/home"}},
    {"session_id":"test-sess-003","user_id":"u2","device_id":"d2","timestamp":'"$(date +%s000)"',"platform":"ios","app_version":"2.0.0","event_type":"error","event_name":"crash","payload":{"message":"NullPointerException"},"context":{"screen_name":"ProductDetail"}}
  ]')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
BODY=$(echo "$RESPONSE" | head -1)
echo "Status: ${HTTP_CODE}"
echo "Body: ${BODY}"
if [ "$HTTP_CODE" = "200" ]; then echo "PASS"; else echo "FAIL"; exit 1; fi
echo ""

# Test 3: Invalid JSON
echo "--- Test 3: Invalid JSON (expect 400) ---"
RESPONSE=$(curl -s -w "\n%{http_code}" -X POST "${EVENTS_URL}" \
  -H "Content-Type: application/json" \
  -d 'not-valid-json{')

HTTP_CODE=$(echo "$RESPONSE" | tail -1)
echo "Status: ${HTTP_CODE}"
if [ "$HTTP_CODE" = "400" ]; then echo "PASS"; else echo "FAIL"; exit 1; fi
echo ""

echo "=== All tests passed ==="
echo ""
echo "Next: Wait ~2 minutes for Firehose buffer to flush, then check S3:"
echo "  aws s3 ls s3://<bucket-name>/raw/ --recursive"
```

- [ ] **Step 2: Make script executable**

```bash
chmod +x rum/scripts/test-ingestion.sh
```

- [ ] **Step 3: Commit**

```bash
git add rum/scripts/test-ingestion.sh
git commit -m "feat(rum): add end-to-end integration test script for ingestion pipeline"
```

---

## Task 10: Final Validation

- [ ] **Step 1: Run all Lambda tests**

```bash
cd rum/lambda/transform && python -m pytest test_handler.py -v
cd rum/lambda/ingest && python -m pytest test_handler.py -v
```

Expected: All 12 tests PASS

- [ ] **Step 2: Run full Terraform validation**

```bash
cd rum/terraform && terraform init -backend=false && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 3: Review resource count with plan**

```bash
cd rum/terraform && terraform plan -var="environment=dev" 2>&1 | tail -5
```

Expected: `Plan: ~25 to add, 0 to change, 0 to destroy.`

- [ ] **Step 4: Final commit (if any uncommitted changes)**

```bash
git status
# If clean: no action needed
# If dirty: git add -A && git commit -m "chore(rum): phase 1a infrastructure complete"
```
