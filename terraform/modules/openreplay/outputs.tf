# terraform/modules/openreplay/outputs.tf
# 모듈 출력값

output "cloudfront_domain" {
  description = "CloudFront 배포 도메인"
  value       = aws_cloudfront_distribution.openreplay.domain_name
}

output "ingest_endpoint" {
  description = "OpenReplay ingest 엔드포인트 URL"
  value       = "https://${aws_cloudfront_distribution.openreplay.domain_name}/ingest"
}

output "rds_endpoint" {
  description = "RDS PostgreSQL 엔드포인트 주소"
  value       = aws_db_instance.openreplay.address
}

output "s3_bucket_name" {
  description = "세션 녹화 S3 버킷 이름"
  value       = aws_s3_bucket.recordings.id
}
