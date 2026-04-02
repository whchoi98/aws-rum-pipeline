# terraform/modules/monitoring/main.tf

# -----------------------------------------------------------------------------
# CloudWatch Dashboard
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "rum" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # -------------------------------------------------------------------------
      # Row 1: API Gateway
      # -------------------------------------------------------------------------
      {
        type   = "metric"
        x      = 0
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "API Requests"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", var.api_id]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "API Errors"
          region = var.region
          period = 300
          metrics = [
            ["AWS/ApiGateway", "4xx", "ApiId", var.api_id, { stat = "Sum", label = "4xx" }],
            ["AWS/ApiGateway", "5xx", "ApiId", var.api_id, { stat = "Sum", label = "5xx" }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 0
        width  = 8
        height = 6
        properties = {
          title  = "API Latency"
          region = var.region
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p50", label = "p50" }],
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p90", label = "p90" }],
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p99", label = "p99" }]
          ]
          view = "timeSeries"
        }
      },
      # -------------------------------------------------------------------------
      # Row 2: Lambda Functions
      # -------------------------------------------------------------------------
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Authorizer"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-authorizer", { stat = "Sum", label = "Invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-authorizer", { stat = "Sum", label = "Errors" }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Ingest Lambda"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-ingest", { stat = "Sum", label = "Invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-ingest", { stat = "Sum", label = "Errors" }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 6
        width  = 8
        height = 6
        properties = {
          title  = "Transform Lambda"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-transform", { stat = "Sum", label = "Invocations" }],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-transform", { stat = "Sum", label = "Errors" }]
          ]
          view = "timeSeries"
        }
      },
      # -------------------------------------------------------------------------
      # Row 3: WAF & Firehose
      # -------------------------------------------------------------------------
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "WAF Requests"
          region = var.region
          period = 300
          metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", "${var.project_name}-waf", "Region", var.region, "Rule", "ALL", { stat = "Sum", label = "Allowed" }],
            ["AWS/WAFV2", "BlockedRequests", "WebACL", "${var.project_name}-waf", "Region", var.region, "Rule", "ALL", { stat = "Sum", label = "Blocked" }]
          ]
          view = "timeSeries"
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 12
        width  = 8
        height = 6
        properties = {
          title  = "Firehose Delivery"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Firehose", "IncomingRecords", "DeliveryStreamName", "${var.project_name}-events", { stat = "Sum", label = "Incoming" }],
            ["AWS/Firehose", "DeliveryToS3.Records", "DeliveryStreamName", "${var.project_name}-events", { stat = "Sum", label = "Delivered to S3" }]
          ]
          view = "timeSeries"
        }
      }
    ]
  })

  tags = var.tags
}
