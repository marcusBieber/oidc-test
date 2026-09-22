resource "aws_ecs_cluster" "this" {
  name = "ecs-demo-${var.environment}"

  tags = {
    Environment = var.environment
  }
}

resource "aws_iam_role" "execution" {
  name_prefix = "ecs-demo-${var.environment}-exec-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "execution" {
  role       = aws_iam_role.execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

locals {
  services = {
    redis-server = {
      image         = var.redis_image
      port          = 6379
      discovery_arn = aws_service_discovery_service.redis.arn
      environment   = []
    }
    yelb-db = {
      image         = var.yelb_db_image
      port          = 5432
      discovery_arn = aws_service_discovery_service.yelb_db.arn
      environment   = []
    }
    yelb-appserver = {
      image         = var.yelb_appserver_image
      port          = 4567
      discovery_arn = aws_service_discovery_service.yelb_appserver.arn
      environment   = []
    }
    yelb-ui = {
      image         = var.yelb_ui_image
      port          = 80
      discovery_arn = null
      environment = [
        { name = "YELB_APPSERVER_ENDPOINT", value = "yelb-appserver.yelb.local:4567" }
      ]
    }
  }
}

resource "aws_cloudwatch_log_group" "this" {
  for_each = local.services

  name              = "/ecs/ecs-demo-${var.environment}/${each.key}"
  retention_in_days = 7

  tags = {
    Environment = var.environment
  }
}

resource "aws_ecs_task_definition" "this" {
  for_each = local.services

  family                   = "ecs-demo-${var.environment}-${each.key}"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = var.container_cpu
  memory                   = var.container_memory
  execution_role_arn       = aws_iam_role.execution.arn

  container_definitions = jsonencode([
    {
      name      = each.key
      image     = each.value.image
      essential = true

      portMappings = [
        {
          containerPort = each.value.port
          protocol      = "tcp"
        }
      ]

      environment = each.value.environment

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this[each.key].name
          "awslogs-region"        = data.aws_region.current.name
          "awslogs-stream-prefix" = each.key
        }
      }
    }
  ])

  tags = {
    Environment = var.environment
  }
}

data "aws_region" "current" {}

resource "aws_ecs_service" "backend" {
  for_each = { for k, v in local.services : k => v if k != "yelb-ui" }

  name            = "${var.environment}-${each.key}"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this[each.key].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public[var.primary_az_index].id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  service_registries {
    registry_arn = each.value.discovery_arn
  }

  tags = {
    Environment = var.environment
  }
}

resource "aws_ecs_service" "yelb_ui" {
  name            = "${var.environment}-yelb-ui"
  cluster         = aws_ecs_cluster.this.id
  task_definition = aws_ecs_task_definition.this["yelb-ui"].arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.public[var.primary_az_index].id]
    security_groups  = [aws_security_group.ecs_tasks.id]
    assign_public_ip = true
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.yelb_ui.arn
    container_name   = "yelb-ui"
    container_port   = 80
  }

  depends_on = [aws_lb_listener.http]

  tags = {
    Environment = var.environment
  }
}
