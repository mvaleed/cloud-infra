# VPC Outputs
output "vpc_id" {
  description = "VPC ID: you'll reference this everywhere"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Where EKS nodes and internal services live"
  value       = module.vpc.private_subnets
}

output "public_subnet_ids" {
  description = "Where ALBs and NAT Gateways live"
  value       = module.vpc.public_subnets
}

output "database_subnet_ids" {
  description = "Isolated subnets for RDS"
  value       = module.vpc.database_subnets
}

# EKS Outputs
output "eks_cluster_name" {
  description = "Cluster name used with: aws eks update-kubeconfig"
  value       = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  description = "API server endpoint"
  value       = module.eks.cluster_endpoint
}

output "eks_oidc_provider_arn" {
  description = "OIDC provider ARN: needed for every IRSA role you create"
  value       = module.eks.oidc_provider_arn
}

# RDS Outputs
output "rds_endpoint" {
  description = "Connection string: host:port"
  value       = module.rds.db_instance_endpoint
}

output "rds_database_name" {
  description = "Database name your app connects to"
  value       = module.rds.db_instance_name
}

output "rds_master_username" {
  description = "Master username for RDS: used by K8s secret creation"
  value       = var.db_master_username
}

# Ingress Outputs
output "traefik_nlb_dns" {
  description = "NLB hostname: point your domain here, or access services directly"
  value       = data.kubernetes_service.traefik.status[0].load_balancer[0].ingress[0].hostname
}
