variable "environment" {
  description = "dev/test/prod - fließt in Ressourcen-Namen und Tags ein"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR-Block der VPC"
  type        = string
  default     = "10.42.0.0/16"
}

# ALB und die RDS-Subnet-Group verlangen Subnets in mindestens 2 AZs (harte
# AWS-Anforderung). Die eigentliche Compute (ECS-Tasks, RDS-Instanz) wird
# trotzdem bewusst nur in primary_az_index geschedult/gepinnt, um dem
# "nur eine AZ"-Wunsch inhaltlich gerecht zu werden.
variable "az_count" {
  description = "Anzahl AZs für das Subnet-Layout (mindestens 2, AWS-Pflicht für ALB/RDS-Subnet-Group)"
  type        = number
  default     = 2
}

variable "primary_az_index" {
  description = "Index (in der Liste der verwendeten AZs) der AZ, in der ECS-Tasks und die RDS-Instanz tatsächlich laufen"
  type        = number
  default     = 0
}

variable "desired_count" {
  description = "Task-Anzahl je ECS-Service (dev bewusst auf Sparflamme = 1)"
  type        = number
  default     = 1
}

variable "container_cpu" {
  description = "CPU-Units je Fargate-Task (kleinste Fargate-Größe für die Demo)"
  type        = number
  default     = 256
}

variable "container_memory" {
  description = "Memory (MiB) je Fargate-Task"
  type        = number
  default     = 512
}

variable "yelb_ui_image" {
  type    = string
  default = "mreferre/yelb-ui:0.10"
}

variable "yelb_appserver_image" {
  type    = string
  default = "mreferre/yelb-appserver:0.7"
}

variable "yelb_db_image" {
  type    = string
  default = "mreferre/yelb-db:0.6"
}

variable "redis_image" {
  type    = string
  default = "redis:4.0.2"
}

variable "db_instance_class" {
  description = "Instanzgröße der (separaten, zusätzlichen) RDS-Postgres-Instanz"
  type        = string
  default     = "db.t4g.micro"
}

variable "db_engine_version" {
  type    = string
  default = "16"
}

variable "db_name" {
  type    = string
  default = "appdb"
}

variable "db_username" {
  type    = string
  default = "appadmin"
}

variable "db_allocated_storage" {
  type    = number
  default = 20
}
