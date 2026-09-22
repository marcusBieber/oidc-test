output "alb_dns_name" {
  description = "URL, unter der die Yelb-Demo im Browser erreichbar ist"
  value       = "http://${aws_lb.this.dns_name}"
}

output "vpc_id" {
  value = aws_vpc.this.id
}

output "rds_endpoint" {
  value = aws_db_instance.this.address
}

output "rds_secret_arn" {
  description = "Secrets-Manager-ARN mit den DB-Credentials"
  value       = aws_secretsmanager_secret.db.arn
}

output "primary_az" {
  value = local.primary_az
}
