# Phase 1c: Managed Grafana + Athena Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deploy Amazon Managed Grafana with Athena data source and 3 RUM dashboards for pipeline observability.

**Architecture:** Terraform module creates Managed Grafana workspace, Athena workgroup, and IAM roles. Dashboard JSON definitions are provisioned via Grafana API. Root main.tf wires the grafana module with outputs from existing modules.

**Tech Stack:** Terraform, Amazon Managed Grafana, Amazon Athena, Grafana Dashboard JSON

**Spec:** `docs/superpowers/specs/2026-04-02-phase1c-grafana-design.md`

---

## File Structure

### New Files

| File | Responsibility |
|------|---------------|
| `terraform/modules/grafana/variables.tf` | Module input variables |
| `terraform/modules/grafana/main.tf` | Grafana workspace + IAM role + Athena workgroup |
| `terraform/modules/grafana/outputs.tf` | Exports: workspace_endpoint, workspace_id, athena_workgroup |
| `terraform/modules/grafana/dashboards/web-vitals.json` | Core Web Vitals dashboard definition |
| `terraform/modules/grafana/dashboards/error-monitoring.json` | Error Monitoring dashboard definition |
| `terraform/modules/grafana/dashboards/traffic-overview.json` | Traffic Overview dashboard definition |
| `scripts/provision-grafana.sh` | Grafana API provisioning script (data source + dashboards) |

### Modified Files

| File | Changes |
|------|---------|
| `terraform/main.tf` | Add `grafana` module block |
| `terraform/outputs.tf` | Add grafana_workspace_endpoint, grafana_workspace_id outputs |

---

## Task 1: Grafana Terraform Module — Variables + IAM

**Files:**
- Create: `terraform/modules/grafana/variables.tf`
- Create: `terraform/modules/grafana/main.tf` (IAM section only)

- [ ] **Step 1: Create variables.tf**

```hcl
# terraform/modules/grafana/variables.tf

variable "project_name" {
  description = "Project name for resource naming and tagging"
  type        = string
}

variable "account_id" {
  description = "AWS account ID"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "s3_bucket_arn" {
  description = "ARN of the S3 data lake bucket (read data + write Athena results)"
  type        = string
}

variable "s3_bucket_name" {
  description = "Name of the S3 data lake bucket"
  type        = string
}

variable "glue_database_name" {
  description = "Glue catalog database name (e.g. rum_pipeline_db)"
  type        = string
}

variable "tags" {
  description = "Additional resource tags"
  type        = map(string)
  default     = {}
}
```

- [ ] **Step 2: Create main.tf with IAM role**

```hcl
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
```

- [ ] **Step 3: Commit**

```bash
git add terraform/modules/grafana/variables.tf terraform/modules/grafana/main.tf
git commit -m "feat(grafana): add Grafana Terraform module variables and IAM role"
```

---

## Task 2: Grafana Workspace + Athena Workgroup + Outputs

**Files:**
- Modify: `terraform/modules/grafana/main.tf` (append workspace + workgroup)
- Create: `terraform/modules/grafana/outputs.tf`

- [ ] **Step 1: Append Grafana workspace and Athena workgroup to main.tf**

Append to `terraform/modules/grafana/main.tf` after the IAM resources:

```hcl
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

  data_sources             = ["ATHENA"]
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

    bytes_scanned_cutoff_per_query = 107374182400  # 100 GB scan limit per query
  }

  tags = var.tags
}
```

- [ ] **Step 2: Create outputs.tf**

```hcl
# terraform/modules/grafana/outputs.tf

output "workspace_endpoint" {
  description = "Amazon Managed Grafana workspace endpoint URL"
  value       = "https://${aws_grafana_workspace.rum.endpoint}"
}

output "workspace_id" {
  description = "Amazon Managed Grafana workspace ID"
  value       = aws_grafana_workspace.rum.id
}

output "athena_workgroup" {
  description = "Athena workgroup name for RUM dashboard queries"
  value       = aws_athena_workgroup.rum.name
}

output "grafana_role_arn" {
  description = "IAM role ARN used by the Grafana workspace"
  value       = aws_iam_role.grafana.arn
}
```

- [ ] **Step 3: Run terraform fmt on the new module**

```bash
cd /home/ec2-user/my-project/rum/terraform && terraform fmt -recursive modules/grafana/
```

Expected: Files formatted (may print file names if changes made)

- [ ] **Step 4: Commit**

```bash
git add terraform/modules/grafana/
git commit -m "feat(grafana): add Grafana workspace, Athena workgroup, and module outputs"
```

---

## Task 3: Root main.tf Wiring

**Files:**
- Modify: `terraform/main.tf`
- Modify: `terraform/outputs.tf`

- [ ] **Step 1: Add grafana module block to terraform/main.tf**

Append to `terraform/main.tf` after the `monitoring` module block:

```hcl
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
```

- [ ] **Step 2: Add grafana outputs to terraform/outputs.tf**

Append to `terraform/outputs.tf`:

```hcl
output "grafana_workspace_endpoint" {
  description = "Amazon Managed Grafana workspace URL"
  value       = module.grafana.workspace_endpoint
}

output "grafana_workspace_id" {
  description = "Amazon Managed Grafana workspace ID"
  value       = module.grafana.workspace_id
}

output "athena_workgroup" {
  description = "Athena workgroup name for RUM queries"
  value       = module.grafana.athena_workgroup
}
```

- [ ] **Step 3: Run terraform validate**

```bash
cd /home/ec2-user/my-project/rum/terraform && terraform init -upgrade && terraform validate
```

Expected: `Success! The configuration is valid.`

- [ ] **Step 4: Commit**

```bash
git add terraform/main.tf terraform/outputs.tf
git commit -m "feat(rum): wire Grafana module into root Terraform configuration"
```

---

## Task 4: Terraform Deploy

**Files:** None (deployment only)

- [ ] **Step 1: Run terraform init**

```bash
cd /home/ec2-user/my-project/rum/terraform && terraform init
```

Expected: `Terraform has been successfully initialized!`

- [ ] **Step 2: Run terraform plan**

```bash
cd /home/ec2-user/my-project/rum/terraform && terraform plan -out=tfplan
```

Expected: Plan shows new resources:
- `module.grafana.aws_iam_role.grafana`
- `module.grafana.aws_iam_role_policy.grafana_athena`
- `module.grafana.aws_grafana_workspace.rum`
- `module.grafana.aws_athena_workgroup.rum`

No existing resources destroyed.

- [ ] **Step 3: Run terraform apply**

```bash
cd /home/ec2-user/my-project/rum/terraform && terraform apply tfplan
```

Expected: 4 resources created successfully.

- [ ] **Step 4: Verify workspace is accessible**

```bash
cd /home/ec2-user/my-project/rum/terraform && terraform output grafana_workspace_endpoint
```

Expected: `https://<workspace-id>.grafana-workspace.ap-northeast-2.amazonaws.com`

Open the URL in a browser and confirm the Grafana login page loads (AWS SSO authentication).

- [ ] **Step 5: Commit any formatting changes**

```bash
cd /home/ec2-user/my-project/rum/terraform && terraform fmt -recursive
git add terraform/
git commit -m "feat(rum): deploy Phase 1c Grafana workspace and Athena workgroup"
```

---

## Task 5: Dashboard JSON — Core Web Vitals

**Files:**
- Create: `terraform/modules/grafana/dashboards/web-vitals.json`

- [ ] **Step 1: Create the Core Web Vitals dashboard JSON**

```json
{
  "title": "RUM — Core Web Vitals",
  "uid": "rum-core-web-vitals",
  "description": "LCP, CLS, and INP p75 metrics from the RUM pipeline",
  "tags": ["rum", "web-vitals"],
  "timezone": "browser",
  "schemaVersion": 38,
  "refresh": "5m",
  "time": { "from": "now-24h", "to": "now" },
  "panels": [
    {
      "id": 1,
      "title": "LCP p75 (ms)",
      "type": "gauge",
      "gridPos": { "x": 0, "y": 0, "w": 6, "h": 6 },
      "options": {
        "reduceOptions": { "calcs": ["lastNotNull"] },
        "orientation": "auto",
        "showThresholdLabels": true,
        "showThresholdMarkers": true
      },
      "fieldConfig": {
        "defaults": {
          "unit": "ms",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 2500 },
              { "color": "red", "value": 4000 }
            ]
          }
        }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75) AS lcp_p75 FROM rum_pipeline_db.rum_events WHERE event_name = 'lcp' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}'",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 2,
      "title": "CLS p75",
      "type": "gauge",
      "gridPos": { "x": 6, "y": 0, "w": 6, "h": 6 },
      "options": {
        "reduceOptions": { "calcs": ["lastNotNull"] },
        "orientation": "auto",
        "showThresholdLabels": true,
        "showThresholdMarkers": true
      },
      "fieldConfig": {
        "defaults": {
          "unit": "none",
          "decimals": 3,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 0.1 },
              { "color": "red", "value": 0.25 }
            ]
          }
        }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75) AS cls_p75 FROM rum_pipeline_db.rum_events WHERE event_name = 'cls' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}'",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 3,
      "title": "INP p75 (ms)",
      "type": "gauge",
      "gridPos": { "x": 12, "y": 0, "w": 6, "h": 6 },
      "options": {
        "reduceOptions": { "calcs": ["lastNotNull"] },
        "orientation": "auto",
        "showThresholdLabels": true,
        "showThresholdMarkers": true
      },
      "fieldConfig": {
        "defaults": {
          "unit": "ms",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 200 },
              { "color": "red", "value": 500 }
            ]
          }
        }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75) AS inp_p75 FROM rum_pipeline_db.rum_events WHERE event_name = 'inp' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}'",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 4,
      "title": "LCP Trend (24h) — p75 per hour",
      "type": "timeseries",
      "gridPos": { "x": 0, "y": 6, "w": 12, "h": 8 },
      "options": {
        "tooltip": { "mode": "single" },
        "legend": { "displayMode": "list", "placement": "bottom" }
      },
      "fieldConfig": {
        "defaults": { "unit": "ms" }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT date_trunc('hour', from_unixtime(timestamp / 1000)) AS time, approx_percentile(CAST(json_extract_scalar(payload, '$.value') AS DOUBLE), 0.75) AS lcp_p75 FROM rum_pipeline_db.rum_events WHERE event_name = 'lcp' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' GROUP BY 1 ORDER BY 1",
          "format": "time_series",
          "timeColumns": ["time"],
          "refId": "A"
        }
      ]
    },
    {
      "id": 5,
      "title": "LCP Rating Distribution",
      "type": "piechart",
      "gridPos": { "x": 12, "y": 6, "w": 6, "h": 8 },
      "options": {
        "pieType": "pie",
        "displayLabels": ["name", "percent"]
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT json_extract_scalar(payload, '$.rating') AS rating, COUNT(*) AS count FROM rum_pipeline_db.rum_events WHERE event_name = 'lcp' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' GROUP BY 1 ORDER BY 1",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 6,
      "title": "Core Web Vitals by Page (p75)",
      "type": "table",
      "gridPos": { "x": 0, "y": 14, "w": 24, "h": 8 },
      "options": {
        "sortBy": [{ "displayName": "LCP p75", "desc": true }]
      },
      "fieldConfig": {
        "overrides": [
          { "matcher": { "id": "byName", "options": "LCP p75" }, "properties": [{ "id": "unit", "value": "ms" }] },
          { "matcher": { "id": "byName", "options": "INP p75" }, "properties": [{ "id": "unit", "value": "ms" }] }
        ]
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT json_extract_scalar(context, '$.url') AS page, approx_percentile(CASE WHEN event_name = 'lcp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75) AS \"LCP p75\", approx_percentile(CASE WHEN event_name = 'cls' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75) AS \"CLS p75\", approx_percentile(CASE WHEN event_name = 'inp' THEN CAST(json_extract_scalar(payload, '$.value') AS DOUBLE) END, 0.75) AS \"INP p75\", COUNT(*) AS samples FROM rum_pipeline_db.rum_events WHERE event_name IN ('lcp', 'cls', 'inp') AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' GROUP BY 1 ORDER BY 2 DESC LIMIT 20",
          "format": "table",
          "refId": "A"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "datasource",
        "type": "datasource",
        "pluginId": "grafana-athena-datasource",
        "label": "Athena Data Source",
        "hide": 0
      }
    ]
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add terraform/modules/grafana/dashboards/web-vitals.json
git commit -m "feat(grafana): add Core Web Vitals dashboard JSON with LCP/CLS/INP panels"
```

---

## Task 6: Dashboard JSON — Error Monitoring

**Files:**
- Create: `terraform/modules/grafana/dashboards/error-monitoring.json`

- [ ] **Step 1: Create the Error Monitoring dashboard JSON**

```json
{
  "title": "RUM — Error Monitoring",
  "uid": "rum-error-monitoring",
  "description": "JavaScript errors, unhandled rejections, and error rate trends",
  "tags": ["rum", "errors"],
  "timezone": "browser",
  "schemaVersion": 38,
  "refresh": "5m",
  "time": { "from": "now-24h", "to": "now" },
  "panels": [
    {
      "id": 1,
      "title": "Error Rate (%)",
      "type": "stat",
      "gridPos": { "x": 0, "y": 0, "w": 6, "h": 4 },
      "options": {
        "reduceOptions": { "calcs": ["lastNotNull"] },
        "colorMode": "background",
        "graphMode": "none",
        "textMode": "value_and_name"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "percent",
          "decimals": 2,
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 1 },
              { "color": "red", "value": 5 }
            ]
          }
        }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT CAST(SUM(CASE WHEN event_type = 'error' THEN 1 ELSE 0 END) AS DOUBLE) * 100.0 / NULLIF(COUNT(*), 0) AS error_rate FROM rum_pipeline_db.rum_events WHERE year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}'",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 2,
      "title": "Total Errors Today",
      "type": "stat",
      "gridPos": { "x": 6, "y": 0, "w": 6, "h": 4 },
      "options": {
        "reduceOptions": { "calcs": ["lastNotNull"] },
        "colorMode": "value",
        "graphMode": "none"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "short",
          "thresholds": {
            "mode": "absolute",
            "steps": [
              { "color": "green", "value": null },
              { "color": "yellow", "value": 100 },
              { "color": "red", "value": 500 }
            ]
          }
        }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT COUNT(*) AS error_count FROM rum_pipeline_db.rum_events WHERE event_type = 'error' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}'",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 3,
      "title": "Error Trend (24h) — errors per hour",
      "type": "timeseries",
      "gridPos": { "x": 0, "y": 4, "w": 16, "h": 8 },
      "options": {
        "tooltip": { "mode": "single" },
        "legend": { "displayMode": "list", "placement": "bottom" }
      },
      "fieldConfig": {
        "defaults": { "unit": "short", "custom": { "drawStyle": "bars", "fillOpacity": 40 } }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT date_trunc('hour', from_unixtime(timestamp / 1000)) AS time, COUNT(*) AS errors FROM rum_pipeline_db.rum_events WHERE event_type = 'error' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' GROUP BY 1 ORDER BY 1",
          "format": "time_series",
          "timeColumns": ["time"],
          "refId": "A"
        }
      ]
    },
    {
      "id": 4,
      "title": "Error by Type",
      "type": "piechart",
      "gridPos": { "x": 16, "y": 4, "w": 8, "h": 8 },
      "options": {
        "pieType": "donut",
        "displayLabels": ["name", "percent"]
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT event_name AS error_type, COUNT(*) AS count FROM rum_pipeline_db.rum_events WHERE event_type = 'error' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' GROUP BY 1 ORDER BY 2 DESC",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 5,
      "title": "Top 10 Error Messages",
      "type": "table",
      "gridPos": { "x": 0, "y": 12, "w": 14, "h": 8 },
      "options": {
        "sortBy": [{ "displayName": "Count", "desc": true }]
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT json_extract_scalar(payload, '$.message') AS error_message, event_name AS error_type, COUNT(*) AS count FROM rum_pipeline_db.rum_events WHERE event_type = 'error' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' GROUP BY 1, 2 ORDER BY 3 DESC LIMIT 10",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 6,
      "title": "Recent Errors (last 20)",
      "type": "table",
      "gridPos": { "x": 0, "y": 20, "w": 24, "h": 8 },
      "options": {
        "sortBy": [{ "displayName": "time", "desc": true }]
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT from_unixtime(timestamp / 1000) AS time, event_name AS error_type, json_extract_scalar(payload, '$.message') AS message, json_extract_scalar(context, '$.url') AS url, platform FROM rum_pipeline_db.rum_events WHERE event_type = 'error' AND year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' ORDER BY timestamp DESC LIMIT 20",
          "format": "table",
          "refId": "A"
        }
      ]
    }
  ],
  "templating": {
    "list": [
      {
        "name": "datasource",
        "type": "datasource",
        "pluginId": "grafana-athena-datasource",
        "label": "Athena Data Source",
        "hide": 0
      }
    ]
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add terraform/modules/grafana/dashboards/error-monitoring.json
git commit -m "feat(grafana): add Error Monitoring dashboard JSON"
```

---

## Task 7: Dashboard JSON — Traffic Overview

**Files:**
- Create: `terraform/modules/grafana/dashboards/traffic-overview.json`

- [ ] **Step 1: Create the Traffic Overview dashboard JSON**

```json
{
  "title": "RUM — Traffic Overview",
  "uid": "rum-traffic-overview",
  "description": "Event volume, page traffic, platform and browser distribution",
  "tags": ["rum", "traffic"],
  "timezone": "browser",
  "schemaVersion": 38,
  "refresh": "5m",
  "time": { "from": "now-24h", "to": "now" },
  "panels": [
    {
      "id": 1,
      "title": "Total Events Today",
      "type": "stat",
      "gridPos": { "x": 0, "y": 0, "w": 6, "h": 4 },
      "options": {
        "reduceOptions": { "calcs": ["lastNotNull"] },
        "colorMode": "value",
        "graphMode": "none"
      },
      "fieldConfig": {
        "defaults": {
          "unit": "short",
          "thresholds": {
            "mode": "absolute",
            "steps": [{ "color": "blue", "value": null }]
          }
        }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT COUNT(*) AS total_events FROM rum_pipeline_db.rum_events WHERE year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}'",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 2,
      "title": "Unique Sessions Today",
      "type": "stat",
      "gridPos": { "x": 6, "y": 0, "w": 6, "h": 4 },
      "options": {
        "reduceOptions": { "calcs": ["lastNotNull"] },
        "colorMode": "value",
        "graphMode": "none"
      },
      "fieldConfig": {
        "defaults": { "unit": "short" }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT COUNT(DISTINCT session_id) AS unique_sessions FROM rum_pipeline_db.rum_events WHERE year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}'",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 3,
      "title": "Events by Type",
      "type": "piechart",
      "gridPos": { "x": 12, "y": 0, "w": 6, "h": 8 },
      "options": {
        "pieType": "pie",
        "displayLabels": ["name", "percent"]
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT event_type, COUNT(*) AS count FROM rum_pipeline_db.rum_events WHERE year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' GROUP BY 1 ORDER BY 2 DESC",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 4,
      "title": "Platform Distribution",
      "type": "piechart",
      "gridPos": { "x": 18, "y": 0, "w": 6, "h": 8 },
      "options": {
        "pieType": "donut",
        "displayLabels": ["name", "percent"]
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT platform, COUNT(*) AS count FROM rum_pipeline_db.rum_events WHERE year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' GROUP BY 1 ORDER BY 2 DESC",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 5,
      "title": "Events Trend (24h) — events per hour",
      "type": "timeseries",
      "gridPos": { "x": 0, "y": 8, "w": 16, "h": 8 },
      "options": {
        "tooltip": { "mode": "multi" },
        "legend": { "displayMode": "table", "placement": "right", "calcs": ["sum"] }
      },
      "fieldConfig": {
        "defaults": { "unit": "short" }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT date_trunc('hour', from_unixtime(timestamp / 1000)) AS time, event_type, COUNT(*) AS events FROM rum_pipeline_db.rum_events WHERE year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' GROUP BY 1, 2 ORDER BY 1",
          "format": "time_series",
          "timeColumns": ["time"],
          "refId": "A"
        }
      ]
    },
    {
      "id": 6,
      "title": "Browser Distribution",
      "type": "barchart",
      "gridPos": { "x": 16, "y": 8, "w": 8, "h": 8 },
      "options": {
        "orientation": "horizontal",
        "xTickLabelMaxLength": 20
      },
      "fieldConfig": {
        "defaults": { "unit": "short" }
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT json_extract_scalar(context, '$.device.browser') AS browser, COUNT(*) AS count FROM rum_pipeline_db.rum_events WHERE year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' AND json_extract_scalar(context, '$.device.browser') IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 10",
          "format": "table",
          "refId": "A"
        }
      ]
    },
    {
      "id": 7,
      "title": "Top Pages by Traffic",
      "type": "table",
      "gridPos": { "x": 0, "y": 16, "w": 24, "h": 8 },
      "options": {
        "sortBy": [{ "displayName": "Events", "desc": true }]
      },
      "targets": [
        {
          "datasource": { "type": "grafana-athena-datasource", "uid": "${datasource}" },
          "rawSQL": "SELECT json_extract_scalar(context, '$.url') AS page, COUNT(*) AS events, COUNT(DISTINCT session_id) AS sessions, CAST(SUM(CASE WHEN event_type = 'error' THEN 1 ELSE 0 END) AS DOUBLE) * 100.0 / NULLIF(COUNT(*), 0) AS error_pct FROM rum_pipeline_db.rum_events WHERE year = '${__from:date:YYYY}' AND month = '${__from:date:MM}' AND day = '${__from:date:DD}' AND json_extract_scalar(context, '$.url') IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 20",
          "format": "table",
          "refId": "A"
        }
      ],
      "fieldConfig": {
        "overrides": [
          { "matcher": { "id": "byName", "options": "error_pct" }, "properties": [{ "id": "unit", "value": "percent" }, { "id": "decimals", "value": 2 }] }
        ]
      }
    }
  ],
  "templating": {
    "list": [
      {
        "name": "datasource",
        "type": "datasource",
        "pluginId": "grafana-athena-datasource",
        "label": "Athena Data Source",
        "hide": 0
      }
    ]
  }
}
```

- [ ] **Step 2: Commit**

```bash
git add terraform/modules/grafana/dashboards/traffic-overview.json
git commit -m "feat(grafana): add Traffic Overview dashboard JSON"
```

---

## Task 8: Dashboard Provisioning Script

**Files:**
- Create: `scripts/provision-grafana.sh`

- [ ] **Step 1: Create the provisioning script**

```bash
#!/usr/bin/env bash
# scripts/provision-grafana.sh
# Provisions Grafana Athena data source and imports 3 RUM dashboards via the Grafana API.
#
# Prerequisites:
#   - GRAFANA_URL: Grafana workspace URL (e.g. https://<id>.grafana-workspace.ap-northeast-2.amazonaws.com)
#   - GRAFANA_API_KEY: Service account token with Admin role
#   - AWS_REGION: AWS region (default: ap-northeast-2)
#   - ATHENA_WORKGROUP: Athena workgroup name (default: rum-pipeline-athena)
#   - S3_BUCKET: S3 bucket name for Athena results (default: rum-pipeline-data-lake-<account-id>)
#   - GLUE_DATABASE: Glue database name (default: rum_pipeline_db)
#   - ACCOUNT_ID: AWS account ID (default: <account-id>)
#
# Usage:
#   export GRAFANA_URL=https://<workspace-id>.grafana-workspace.ap-northeast-2.amazonaws.com
#   export GRAFANA_API_KEY=<service-account-token>
#   ./scripts/provision-grafana.sh

set -euo pipefail

GRAFANA_URL="${GRAFANA_URL:?Set GRAFANA_URL to the Grafana workspace URL}"
GRAFANA_API_KEY="${GRAFANA_API_KEY:?Set GRAFANA_API_KEY to a Grafana service account token}"
AWS_REGION="${AWS_REGION:-ap-northeast-2}"
ATHENA_WORKGROUP="${ATHENA_WORKGROUP:-rum-pipeline-athena}"
S3_BUCKET="${S3_BUCKET:-rum-pipeline-data-lake-<account-id>}"
GLUE_DATABASE="${GLUE_DATABASE:-rum_pipeline_db}"
ACCOUNT_ID="${ACCOUNT_ID:-<account-id>}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DASHBOARDS_DIR="${SCRIPT_DIR}/../terraform/modules/grafana/dashboards"

GRAFANA_API="${GRAFANA_URL}/api"
AUTH_HEADER="Authorization: Bearer ${GRAFANA_API_KEY}"
CONTENT_HEADER="Content-Type: application/json"

echo "=== Grafana RUM Dashboard Provisioning ==="
echo "Workspace: ${GRAFANA_URL}"
echo "Region:    ${AWS_REGION}"
echo "Workgroup: ${ATHENA_WORKGROUP}"
echo "Bucket:    s3://${S3_BUCKET}/athena-results/"
echo ""

# ── Step 1: Verify Grafana connectivity ──────────────────────────────────────
echo "--- Step 1: Verify Grafana connectivity ---"
HTTP_CODE=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "${AUTH_HEADER}" \
  "${GRAFANA_API}/health")
if [ "${HTTP_CODE}" != "200" ]; then
  echo "FAIL: Cannot reach Grafana API (HTTP ${HTTP_CODE}). Check GRAFANA_URL and GRAFANA_API_KEY."
  exit 1
fi
echo "PASS: Grafana API reachable"
echo ""

# ── Step 2: Create Athena data source ────────────────────────────────────────
echo "--- Step 2: Create Athena data source ---"
DATASOURCE_PAYLOAD=$(cat <<EOF
{
  "name": "Amazon Athena — RUM Pipeline",
  "type": "grafana-athena-datasource",
  "access": "proxy",
  "isDefault": true,
  "jsonData": {
    "authType": "default",
    "defaultRegion": "${AWS_REGION}",
    "catalog": "AwsDataCatalog",
    "database": "${GLUE_DATABASE}",
    "workgroup": "${ATHENA_WORKGROUP}",
    "outputLocation": "s3://${S3_BUCKET}/athena-results/"
  }
}
EOF
)

DS_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
  -H "${AUTH_HEADER}" \
  -H "${CONTENT_HEADER}" \
  -d "${DATASOURCE_PAYLOAD}" \
  "${GRAFANA_API}/datasources")

DS_HTTP_CODE=$(echo "${DS_RESPONSE}" | tail -1)
DS_BODY=$(echo "${DS_RESPONSE}" | head -1)

if [ "${DS_HTTP_CODE}" = "200" ] || [ "${DS_HTTP_CODE}" = "409" ]; then
  echo "PASS: Athena data source created (HTTP ${DS_HTTP_CODE})"
  if [ "${DS_HTTP_CODE}" = "409" ]; then
    echo "      (409 = already exists, skipping)"
  fi
else
  echo "FAIL: Could not create data source (HTTP ${DS_HTTP_CODE})"
  echo "      Response: ${DS_BODY}"
  exit 1
fi
echo ""

# ── Step 3: Import dashboards ────────────────────────────────────────────────
echo "--- Step 3: Import dashboards ---"

DASHBOARD_FILES=(
  "web-vitals.json"
  "error-monitoring.json"
  "traffic-overview.json"
)

for DASHBOARD_FILE in "${DASHBOARD_FILES[@]}"; do
  DASHBOARD_PATH="${DASHBOARDS_DIR}/${DASHBOARD_FILE}"
  if [ ! -f "${DASHBOARD_PATH}" ]; then
    echo "FAIL: Dashboard file not found: ${DASHBOARD_PATH}"
    exit 1
  fi

  DASHBOARD_TITLE=$(python3 -c "import json,sys; d=json.load(open('${DASHBOARD_PATH}')); print(d['title'])")

  IMPORT_PAYLOAD=$(cat <<EOF
{
  "dashboard": $(cat "${DASHBOARD_PATH}"),
  "overwrite": true,
  "folderId": 0,
  "inputs": []
}
EOF
)

  IMPORT_RESPONSE=$(curl -s -w "\n%{http_code}" -X POST \
    -H "${AUTH_HEADER}" \
    -H "${CONTENT_HEADER}" \
    -d "${IMPORT_PAYLOAD}" \
    "${GRAFANA_API}/dashboards/import")

  IMPORT_HTTP_CODE=$(echo "${IMPORT_RESPONSE}" | tail -1)
  IMPORT_BODY=$(echo "${IMPORT_RESPONSE}" | head -1)

  if [ "${IMPORT_HTTP_CODE}" = "200" ]; then
    DASHBOARD_URL=$(echo "${IMPORT_BODY}" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('importedUrl', 'unknown'))" 2>/dev/null || echo "unknown")
    echo "PASS: Imported '${DASHBOARD_TITLE}'"
    echo "      URL: ${GRAFANA_URL}${DASHBOARD_URL}"
  else
    echo "FAIL: Could not import '${DASHBOARD_TITLE}' (HTTP ${IMPORT_HTTP_CODE})"
    echo "      Response: ${IMPORT_BODY}"
    exit 1
  fi
done

echo ""
echo "=== Provisioning complete ==="
echo ""
echo "Open Grafana: ${GRAFANA_URL}"
echo "Dashboards are in the General folder."
echo ""
echo "Next: Run the RUM simulator to generate data, then refresh the dashboards."
echo "  python3 scripts/rum-simulator.py --endpoint \$(cd terraform && terraform output -raw api_endpoint) --count 100"
```

- [ ] **Step 2: Make the script executable**

```bash
chmod +x /home/ec2-user/my-project/rum/scripts/provision-grafana.sh
```

- [ ] **Step 3: Test the script (dry run — verify it fails gracefully without credentials)**

```bash
GRAFANA_URL=https://placeholder.grafana-workspace.ap-northeast-2.amazonaws.com \
GRAFANA_API_KEY=placeholder \
bash -n /home/ec2-user/my-project/rum/scripts/provision-grafana.sh
```

Expected: `bash -n` (syntax check) exits 0. Runtime with placeholder credentials will fail at Step 1 (expected).

- [ ] **Step 4: Run provisioning against live workspace**

After `terraform apply` from Task 4, create a Grafana service account token:

```bash
# 1. Get workspace ID and URL
WORKSPACE_ID=$(cd /home/ec2-user/my-project/rum/terraform && terraform output -raw grafana_workspace_id)
GRAFANA_URL=$(cd /home/ec2-user/my-project/rum/terraform && terraform output -raw grafana_workspace_endpoint)

# 2. Create a service account via AWS CLI
aws grafana create-workspace-service-account \
  --workspace-id "${WORKSPACE_ID}" \
  --name "terraform-provisioner" \
  --grafana-role "ADMIN" \
  --region ap-northeast-2

# 3. Create token for the service account (replace <service-account-id> with output from above)
SERVICE_ACCOUNT_ID=<service-account-id>
TOKEN_RESPONSE=$(aws grafana create-workspace-service-account-token \
  --workspace-id "${WORKSPACE_ID}" \
  --service-account-id "${SERVICE_ACCOUNT_ID}" \
  --name "provision-$(date +%Y%m%d)" \
  --seconds-to-live 3600 \
  --region ap-northeast-2)

GRAFANA_API_KEY=$(echo "${TOKEN_RESPONSE}" | python3 -c "import json,sys; print(json.load(sys.stdin)['serviceAccountToken']['key'])")

# 4. Run provisioning
GRAFANA_URL="${GRAFANA_URL}" GRAFANA_API_KEY="${GRAFANA_API_KEY}" \
  /home/ec2-user/my-project/rum/scripts/provision-grafana.sh
```

Expected output:
```
=== Grafana RUM Dashboard Provisioning ===
...
PASS: Grafana API reachable
PASS: Athena data source created (HTTP 200)
PASS: Imported 'RUM — Core Web Vitals'
      URL: https://<workspace>.grafana-workspace.../d/rum-core-web-vitals
PASS: Imported 'RUM — Error Monitoring'
      URL: https://<workspace>.grafana-workspace.../d/rum-error-monitoring
PASS: Imported 'RUM — Traffic Overview'
      URL: https://<workspace>.grafana-workspace.../d/rum-traffic-overview
=== Provisioning complete ===
```

- [ ] **Step 5: Verify dashboards appear in Grafana UI**

Open `${GRAFANA_URL}` in a browser (AWS SSO login required), navigate to Dashboards > Browse, and confirm 3 dashboards are present.

- [ ] **Step 6: Commit**

```bash
git add scripts/provision-grafana.sh
git commit -m "feat(grafana): add Grafana provisioning script for Athena data source and dashboards"
```
