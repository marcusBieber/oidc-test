data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs        = slice(data.aws_availability_zones.available.names, 0, var.az_count)
  primary_az = local.azs[var.primary_az_index]
}

resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name        = "ecs-demo-${var.environment}"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "ecs-demo-${var.environment}"
    Environment = var.environment
  }
}

# Ein öffentliches Subnet je AZ. Fargate-Tasks bekommen eine Public IP
# (assign_public_ip = true), damit sie ohne NAT Gateway nach außen können
# (Docker-Hub-Images ziehen etc.) - bewusste Vereinfachung für die Demo,
# in einem produktiven Setup würde man das auf private Subnets + NAT
# umstellen.
resource "aws_subnet" "public" {
  count = var.az_count

  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)
  map_public_ip_on_launch = true

  tags = {
    Name        = "ecs-demo-${var.environment}-public-${local.azs[count.index]}"
    Environment = var.environment
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.this.id
  }

  tags = {
    Name        = "ecs-demo-${var.environment}-public"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count = var.az_count

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private Subnets ausschließlich für RDS - kein Internetzugang nötig, daher
# kein NAT Gateway (spart Kosten). Nur lokales VPC-Routing (Default-Route
# der Route Table), keine Route zum Internet Gateway.
resource "aws_subnet" "private" {
  count = var.az_count

  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + var.az_count)

  tags = {
    Name        = "ecs-demo-${var.environment}-private-${local.azs[count.index]}"
    Environment = var.environment
  }
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id

  tags = {
    Name        = "ecs-demo-${var.environment}-private"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "private" {
  count = var.az_count

  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}
