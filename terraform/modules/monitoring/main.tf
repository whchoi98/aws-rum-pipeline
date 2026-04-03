# terraform/modules/monitoring/main.tf

# -----------------------------------------------------------------------------
# CloudWatch Dashboard — RUM 파이프라인 운영 대시보드
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_dashboard" "rum" {
  dashboard_name = "${var.project_name}-dashboard"

  dashboard_body = jsonencode({
    widgets = [
      # =====================================================================
      # Row 0: 헤더 텍스트
      # =====================================================================
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 2
        properties = {
          markdown = "# RUM 파이프라인 운영 대시보드\nAPI Gateway → Lambda Authorizer → Ingest Lambda → Kinesis Firehose → S3 Data Lake"
        }
      },

      # =====================================================================
      # Row 1: API Gateway 주요 지표 (숫자)
      # =====================================================================
      {
        type   = "metric"
        x      = 0
        y      = 2
        width  = 6
        height = 4
        properties = {
          title  = "API 총 요청 수"
          region = var.region
          period = 3600
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", var.api_id]
          ]
          view      = "singleValue"
          sparkline = true
        }
      },
      {
        type   = "metric"
        x      = 6
        y      = 2
        width  = 6
        height = 4
        properties = {
          title  = "4xx 클라이언트 에러"
          region = var.region
          period = 3600
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "4xx", "ApiId", var.api_id]
          ]
          view      = "singleValue"
          sparkline = true
          yAxis     = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 2
        width  = 6
        height = 4
        properties = {
          title  = "5xx 서버 에러"
          region = var.region
          period = 3600
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "5xx", "ApiId", var.api_id]
          ]
          view      = "singleValue"
          sparkline = true
          yAxis     = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 18
        y      = 2
        width  = 6
        height = 4
        properties = {
          title  = "API 평균 지연 시간"
          region = var.region
          period = 3600
          stat   = "Average"
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id]
          ]
          view      = "singleValue"
          sparkline = true
        }
      },

      # =====================================================================
      # Row 2: API Gateway 시계열
      # =====================================================================
      {
        type   = "metric"
        x      = 0
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "API 요청 추이"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "Count", "ApiId", var.api_id, { label = "요청 수" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "요청 수" } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 6
        width  = 12
        height = 6
        properties = {
          title  = "API 에러 추이"
          region = var.region
          period = 300
          metrics = [
            ["AWS/ApiGateway", "4xx", "ApiId", var.api_id, { stat = "Sum", label = "4xx 에러", color = "#FF9830" }],
            ["AWS/ApiGateway", "5xx", "ApiId", var.api_id, { stat = "Sum", label = "5xx 에러", color = "#F2495C" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "에러 수" } }
        }
      },

      # =====================================================================
      # Row 3: API 지연 시간 상세
      # =====================================================================
      {
        type   = "metric"
        x      = 0
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "API 지연 시간 백분위수"
          region = var.region
          period = 300
          metrics = [
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p50", label = "p50 (중앙값)" }],
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p90", label = "p90" }],
            ["AWS/ApiGateway", "Latency", "ApiId", var.api_id, { stat = "p99", label = "p99" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "ms" } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 12
        width  = 12
        height = 6
        properties = {
          title  = "API 데이터 처리량"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/ApiGateway", "DataProcessed", "ApiId", var.api_id, { label = "데이터 처리량" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "Bytes" } }
        }
      },

      # =====================================================================
      # Row 4: Lambda 함수 — 호출 + 에러
      # =====================================================================
      {
        type   = "metric"
        x      = 0
        y      = 18
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Authorizer (인증)"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-authorizer", { stat = "Sum", label = "호출 수", color = "#3B78E7" }],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-authorizer", { stat = "Sum", label = "에러 수", color = "#F2495C" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 18
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Ingest (수집)"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-ingest", { stat = "Sum", label = "호출 수", color = "#3B78E7" }],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-ingest", { stat = "Sum", label = "에러 수", color = "#F2495C" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 18
        width  = 8
        height = 6
        properties = {
          title  = "Lambda Transform (변환)"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Invocations", "FunctionName", "${var.project_name}-transform", { stat = "Sum", label = "호출 수", color = "#3B78E7" }],
            ["AWS/Lambda", "Errors", "FunctionName", "${var.project_name}-transform", { stat = "Sum", label = "에러 수", color = "#F2495C" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0 } }
        }
      },

      # =====================================================================
      # Row 5: Lambda 실행 시간
      # =====================================================================
      {
        type   = "metric"
        x      = 0
        y      = 24
        width  = 8
        height = 6
        properties = {
          title  = "Authorizer 실행 시간"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-authorizer", { stat = "Average", label = "평균", color = "#73BF69" }],
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-authorizer", { stat = "p99", label = "p99", color = "#FF9830" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "ms" } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 24
        width  = 8
        height = 6
        properties = {
          title  = "Ingest 실행 시간"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-ingest", { stat = "Average", label = "평균", color = "#73BF69" }],
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-ingest", { stat = "p99", label = "p99", color = "#FF9830" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "ms" } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 24
        width  = 8
        height = 6
        properties = {
          title  = "Transform 실행 시간"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-transform", { stat = "Average", label = "평균", color = "#73BF69" }],
            ["AWS/Lambda", "Duration", "FunctionName", "${var.project_name}-transform", { stat = "p99", label = "p99", color = "#FF9830" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "ms" } }
        }
      },

      # =====================================================================
      # Row 6: Lambda 동시 실행 + 스로틀
      # =====================================================================
      {
        type   = "metric"
        x      = 0
        y      = 30
        width  = 12
        height = 6
        properties = {
          title  = "Lambda 동시 실행 수"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", "${var.project_name}-authorizer", { stat = "Maximum", label = "Authorizer" }],
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", "${var.project_name}-ingest", { stat = "Maximum", label = "Ingest" }],
            ["AWS/Lambda", "ConcurrentExecutions", "FunctionName", "${var.project_name}-transform", { stat = "Maximum", label = "Transform" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "동시 실행" } }
        }
      },
      {
        type   = "metric"
        x      = 12
        y      = 30
        width  = 12
        height = 6
        properties = {
          title  = "Lambda 스로틀 횟수"
          region = var.region
          period = 300
          metrics = [
            ["AWS/Lambda", "Throttles", "FunctionName", "${var.project_name}-authorizer", { stat = "Sum", label = "Authorizer" }],
            ["AWS/Lambda", "Throttles", "FunctionName", "${var.project_name}-ingest", { stat = "Sum", label = "Ingest" }],
            ["AWS/Lambda", "Throttles", "FunctionName", "${var.project_name}-transform", { stat = "Sum", label = "Transform" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "스로틀 횟수" } }
        }
      },

      # =====================================================================
      # Row 7: WAF
      # =====================================================================
      {
        type   = "metric"
        x      = 0
        y      = 36
        width  = 8
        height = 6
        properties = {
          title  = "WAF 허용/차단 요청"
          region = var.region
          period = 300
          metrics = [
            ["AWS/WAFV2", "AllowedRequests", "WebACL", "${var.project_name}-waf", "Region", var.region, "Rule", "ALL", { stat = "Sum", label = "허용", color = "#73BF69" }],
            ["AWS/WAFV2", "BlockedRequests", "WebACL", "${var.project_name}-waf", "Region", var.region, "Rule", "ALL", { stat = "Sum", label = "차단", color = "#F2495C" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "요청 수" } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 36
        width  = 8
        height = 6
        properties = {
          title  = "WAF Rate Limit 차단"
          region = var.region
          period = 300
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", "${var.project_name}-waf", "Region", var.region, "Rule", "rate-limit", { stat = "Sum", label = "Rate Limit 차단", color = "#FF9830" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0 } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 36
        width  = 8
        height = 6
        properties = {
          title  = "WAF Bot Control 차단"
          region = var.region
          period = 300
          metrics = [
            ["AWS/WAFV2", "BlockedRequests", "WebACL", "${var.project_name}-waf", "Region", var.region, "Rule", "bot-control", { stat = "Sum", label = "Bot 차단", color = "#F2495C" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0 } }
        }
      },

      # =====================================================================
      # Row 8: Kinesis Firehose
      # =====================================================================
      {
        type   = "metric"
        x      = 0
        y      = 42
        width  = 8
        height = 6
        properties = {
          title  = "Firehose 수신 레코드"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Firehose", "IncomingRecords", "DeliveryStreamName", "${var.project_name}-events", { label = "수신 레코드" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "레코드 수" } }
        }
      },
      {
        type   = "metric"
        x      = 8
        y      = 42
        width  = 8
        height = 6
        properties = {
          title  = "Firehose S3 전송"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Firehose", "DeliveryToS3.Records", "DeliveryStreamName", "${var.project_name}-events", { label = "S3 전송 레코드", color = "#73BF69" }],
            ["AWS/Firehose", "DeliveryToS3.Success", "DeliveryStreamName", "${var.project_name}-events", { label = "S3 전송 성공", color = "#3B78E7" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "레코드 수" } }
        }
      },
      {
        type   = "metric"
        x      = 16
        y      = 42
        width  = 8
        height = 6
        properties = {
          title  = "Firehose 수신 바이트"
          region = var.region
          period = 300
          stat   = "Sum"
          metrics = [
            ["AWS/Firehose", "IncomingBytes", "DeliveryStreamName", "${var.project_name}-events", { label = "수신 바이트" }]
          ]
          view  = "timeSeries"
          yAxis = { left = { min = 0, label = "Bytes" } }
        }
      }
    ]
  })
}
