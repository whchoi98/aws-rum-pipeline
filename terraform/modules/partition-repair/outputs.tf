# terraform/modules/partition-repair/outputs.tf

output "lambda_function_name" {
  description = "Partition repair Lambda function name"
  value       = aws_lambda_function.partition_repair.function_name
}

output "schedule_rule_name" {
  description = "EventBridge schedule rule name"
  value       = aws_cloudwatch_event_rule.partition_repair.name
}
