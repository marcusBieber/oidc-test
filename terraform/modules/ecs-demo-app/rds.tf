# Separate, eigenständige RDS-Postgres-Instanz - Stand-in für das
# "AWS managed PostgreSQL"-Muster des Kunden. Yelb selbst bringt seine
# eigene DB (yelb-db-Container, siehe ecs.tf) mit und nutzt diese RDS
# Instanz nicht aktiv; sie dient hier nur dem Infrastruktur-Nachweis
# (VPC-Konnektivität, Subnet-Group, Secrets Manager, Single-AZ-Pinning).
resource "aws_db_subnet_group" "this" {
  name_prefix = "ecs-demo-${var.environment}-"
  subnet_ids  = aws_subnet.private[*].id

  tags = {
    Name        = "ecs-demo-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_db_instance" "this" {
  identifier_prefix = "ecs-demo-${var.environment}-"

  engine         = "postgres"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = var.db_allocated_storage
  storage_encrypted = true

  db_name  = var.db_name
  username = var.db_username
  password = random_password.db.result

  db_subnet_group_name   = aws_db_subnet_group.this.name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # Bewusst nur in einer AZ (Kundenwunsch) statt Multi-AZ-Failover.
  multi_az          = false
  availability_zone = local.primary_az

  publicly_accessible = false
  skip_final_snapshot = true

  tags = {
    Name        = "ecs-demo-${var.environment}"
    Environment = var.environment
  }
}
