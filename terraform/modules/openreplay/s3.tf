# terraform/modules/openreplay/s3.tf
# 세션 녹화 저장용 S3 버킷

data "aws_caller_identity" "current" {}

resource "aws_s3_bucket" "recordings" {
  bucket = "${var.project_name}-openreplay-recordings-${data.aws_caller_identity.current.account_id}"

  tags = merge(var.tags, { Name = "${var.project_name}-openreplay-recordings" })
}

# SSE-S3 기본 암호화
resource "aws_s3_bucket_server_side_encryption_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# 퍼블릭 액세스 완전 차단
resource "aws_s3_bucket_public_access_block" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# 라이프사이클 규칙: 30일→IA, 90일→Glacier, 365일→삭제
resource "aws_s3_bucket_lifecycle_configuration" "recordings" {
  bucket = aws_s3_bucket.recordings.id

  rule {
    id     = "recordings-lifecycle"
    status = "Enabled"

    transition {
      days          = 30
      storage_class = "STANDARD_IA"
    }

    transition {
      days          = 90
      storage_class = "GLACIER"
    }

    expiration {
      days = 365
    }
  }
}
