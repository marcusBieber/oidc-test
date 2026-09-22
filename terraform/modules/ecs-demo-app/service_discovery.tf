# Yelb erwartet die internen Hostnamen "redis-server", "yelb-db" und
# "yelb-appserver" (fest im App-Code der jeweiligen Client-Container
# verankert, nicht per Env-Var konfigurierbar) - Cloud Map bildet diese
# Namen als private DNS-Einträge innerhalb der VPC nach.
resource "aws_service_discovery_private_dns_namespace" "this" {
  name = "yelb.local"
  vpc  = aws_vpc.this.id
}

resource "aws_service_discovery_service" "redis" {
  name = "redis-server"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "yelb_db" {
  name = "yelb-db"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}

resource "aws_service_discovery_service" "yelb_appserver" {
  name = "yelb-appserver"

  dns_config {
    namespace_id = aws_service_discovery_private_dns_namespace.this.id

    dns_records {
      ttl  = 10
      type = "A"
    }
  }

  health_check_custom_config {
    failure_threshold = 1
  }
}
