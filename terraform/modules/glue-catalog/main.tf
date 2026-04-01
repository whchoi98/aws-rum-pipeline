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
