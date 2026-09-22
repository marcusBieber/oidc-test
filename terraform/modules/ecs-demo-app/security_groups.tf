resource "aws_security_group" "alb" {
  name_prefix = "ecs-demo-${var.environment}-alb-"
  description = "ALB - HTTP von außen"
  vpc_id      = aws_vpc.this.id

  ingress {
    description = "HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ecs-demo-${var.environment}-alb"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Eine gemeinsame Security Group für alle ECS-Services (ui, appserver,
# redis-server, yelb-db). Traffic zwischen den Services läuft über Cloud
# Map/DNS, nicht über localhost (jeder Service ist ein eigener Task) -
# daher braucht es hier eine self-referencing Ingress-Regel.
resource "aws_security_group" "ecs_tasks" {
  name_prefix = "ecs-demo-${var.environment}-tasks-"
  description = "ECS Tasks - Traffic vom ALB und untereinander"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Vom ALB (yelb-ui)"
    from_port       = 0
    to_port         = 65535
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ecs-demo-${var.environment}-tasks"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group_rule" "ecs_tasks_self" {
  description              = "Traffic zwischen den ECS-Services (ui -> appserver -> redis/db)"
  type                     = "ingress"
  from_port                = 0
  to_port                  = 65535
  protocol                 = "tcp"
  security_group_id        = aws_security_group.ecs_tasks.id
  source_security_group_id = aws_security_group.ecs_tasks.id
}

resource "aws_security_group" "rds" {
  name_prefix = "ecs-demo-${var.environment}-rds-"
  description = "RDS Postgres - nur von den ECS Tasks erreichbar"
  vpc_id      = aws_vpc.this.id

  ingress {
    description     = "Postgres von den ECS Tasks"
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs_tasks.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name        = "ecs-demo-${var.environment}-rds"
    Environment = var.environment
  }

  lifecycle {
    create_before_destroy = true
  }
}
