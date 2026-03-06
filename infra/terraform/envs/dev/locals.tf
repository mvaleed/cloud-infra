
locals {
  # Dev: 2 AZs (minimum for EKS & RDS subnet group requirements)
  # PROD: Change to 3. EKS control plane spreads across 3 AZs
  # for HA. RDS Multi-AZ failover works better with 3 options.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  name = "${var.project_name}-${var.environment}"
}
