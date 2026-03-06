data "aws_availability_zones" "available" {
  state = "available"
  # Filters out Local Zones and Wavelength Zones which can cause
  # weird subnet issues with EKS.
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

# ------------------------------------------------------------------
# VPC
# ------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 6.6"

  name = "${local.name}-vpc"
  cidr = var.vpc_cidr
  azs  = local.azs

  # - Public:   ALB, NAT Gateway, bastion (if needed)
  # - Private:  EKS nodes, internal services
  # - Database: RDS only. Isolated. No internet route at all.

  public_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  # Result: 10.0.0.0/20, 10.0.16.0/20

  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 4)]
  # Result: 10.0.64.0/20, 10.0.80.0/20

  database_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k + 8)]
  # Result: 10.0.128.0/20, 10.0.144.0/20

  # ------------------------------------------------------------------
  # NAT GATEWAY
  # ------------------------------------------------------------------
  # Dev: 1 NAT Gateway (~$32/mo). Good enough.
  # PROD: Set enable_nat_gateway = true, one_nat_gateway_per_az = true
  # Why? If the AZ hosting your single NAT GW goes down, ALL private
  # subnets lose internet. In prod, each AZ needs its own.

  enable_nat_gateway = true
  single_nat_gateway = true # PROD: false
  # one_nat_gateway_per_az = true  # PROD: uncomment this

  # ------------------------------------------------------------------
  # DATABASE SUBNET GROUP
  # ------------------------------------------------------------------
  # This auto-creates an RDS subnet group from database_subnets.
  # Without this, you'd need to create aws_db_subnet_group manually.

  create_database_subnet_group       = true
  create_database_subnet_route_table = true

  # No NAT route for DB subnets — they stay fully isolated.
  create_database_internet_gateway_route = false
  create_database_nat_gateway_route      = false

  # ------------------------------------------------------------------
  # DNS SETTINGS
  # ------------------------------------------------------------------
  # Both required for private DNS resolution (e.g., RDS endpoints,
  # service discovery, and EKS internal DNS).

  enable_dns_hostnames = true
  enable_dns_support   = true

  # ------------------------------------------------------------------
  # SUBNET TAGS — EKS needs these to discover subnets.
  # ------------------------------------------------------------------
  # The AWS Load Balancer Controller uses these tags to know where
  # to place ALBs (public) and internal NLBs (private).
  # Without these, your Ingress objects won't create load balancers.

  public_subnet_tags = {
    "kubernetes.io/role/elb"                  = 1
    "kubernetes.io/cluster/${local.name}-eks" = "shared"
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb"         = 1
    "kubernetes.io/cluster/${local.name}-eks" = "shared"
  }

  database_subnet_tags = {
    "Tier" = "database"
  }

  # ------------------------------------------------------------------
  # VPC FLOW LOGS — enabled even in dev (lightweight config)
  # ------------------------------------------------------------------
  # Logs network traffic metadata (not payload) to CloudWatch.
  # Essential for debugging connectivity issues and security audits.
  # In dev, 600s aggregation + 7-day retention keeps costs negligible.
  #
  # PROD: Reduce aggregation to 60s and increase retention to 30+ days.
  # Also consider S3 as destination for long-term / cheaper storage.

  enable_flow_log                      = true
  create_flow_log_cloudwatch_log_group = true
  create_flow_log_cloudwatch_iam_role  = true
  flow_log_max_aggregation_interval    = 600 # PROD: 60

  flow_log_cloudwatch_log_group_retention_in_days = 7 # PROD: 30+

  # Only capture rejected traffic in dev — keeps volume (and cost) low
  # while still showing you what's being blocked.
  flow_log_traffic_type = "REJECT" # PROD: "ALL"

  # ------------------------------------------------------------------
  # DEFAULT SECURITY GROUP — lock it down
  # ------------------------------------------------------------------
  # AWS creates a default SG with allow-all rules. That's a security
  # hazard if anything accidentally uses it. Zero out its rules so
  # it effectively blocks everything. All real traffic should flow
  # through purpose-built security groups (EKS, RDS, ALB, etc.).

  manage_default_security_group  = true
  default_security_group_ingress = []
  default_security_group_egress  = []
}
