output "database_name" {
  description = "Glue catalog database name"
  value       = aws_glue_catalog_database.rum.name
}

output "rum_events_table_name" {
  description = "Glue table name for raw RUM events"
  value       = aws_glue_catalog_table.rum_events.name
}
