# ------------------------------------------------------------------
# SECURITY GROUP FOR RDS
# ------------------------------------------------------------------
# RDS needs a security group that ONLY allows traffic from EKS nodes.
# The DB sits in isolated subnets, but security groups are the
# second line of defense (defense-in-depth).

resource "aws_security_group" "rds" {
  name_prefix = "${local.name}-rds"
  description = "Allow PostgreSQL access from EKS nodes only"
  vpc_id      = module.vpc.vpc_id

  ingress {
    description = "PostgreSQL from EKS nodes"
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    # Reference the EKS node security group — only pods on those
    # nodes can reach the database.
    security_groups = [module.eks.node_security_group_id]
  }

  # No egress rule for RDS. It doesn't need to initiate connections.
  # AWS adds a default allow-all egress, but RDS in isolated subnets
  # with no route table to the internet means it goes nowhere anyway.

  tags = {
    Name = "${local.name}-rds-sg"
  }

  lifecycle {
    create_before_destroy = true
  }
}

# ------------------------------------------------------------------
# RDS POSTGRESQL
# ------------------------------------------------------------------
# UPGRADE NOTE (v7.x):
#   Module v7.0+ requires Terraform >= 1.11 and AWS provider >= 6.27.
#   The `password` argument was removed — use `password_wo` + `password_wo_version`.
#   Variable types changed from `any` to strict object types.
#   See: https://github.com/terraform-aws-modules/terraform-aws-rds/releases/tag/v7.0.0

module "rds" {
  source  = "terraform-aws-modules/rds/aws"
  version = "~> 7.1"

  identifier = "${local.name}-postgres"

  # ----------------------------------------------------------------
  # ENGINE
  # ----------------------------------------------------------------
  engine               = "postgres"
  engine_version       = "16.11"      # Was 16.2 — upgrade to latest PG 16 minor
  family               = "postgres16" # For parameter group
  major_engine_version = "16"         # For option group

  # ----------------------------------------------------------------
  # INSTANCE SIZE
  # ----------------------------------------------------------------
  # db.t4g.micro: 2 vCPU, 1 GB RAM, ARM-based (cheaper).
  # Free tier eligible. Fine for dev with <10 microservices.
  #
  # PROD: Use db.r6g.large or db.r7g.large (memory-optimized).
  # Delivery apps are read-heavy (menu browsing, order status checks).
  # Memory-optimized = bigger buffer pool = more data cached in RAM.
  # Also add read replicas for read-heavy services.

  instance_class = "db.t4g.micro" # PROD: db.r6g.large

  # ----------------------------------------------------------------
  # STORAGE
  # ----------------------------------------------------------------
  allocated_storage     = 20    # GB, starting size
  max_allocated_storage = 100   # Auto-scales up to this. AWS handles it.
  storage_type          = "gp3" # gp3 has baseline 3000 IOPS free (vs gp2's 100/GB).
  # PROD: For high-write workloads (order transactions), consider
  # io2 with provisioned IOPS. But gp3 handles most cases up to
  # serious scale.

  # ----------------------------------------------------------------
  # ENCRYPTION — enable even in dev
  # ----------------------------------------------------------------
  storage_encrypted = true # Uses default aws/rds KMS key. Zero cost, no reason to skip.
  # PROD: Use a customer-managed KMS key for cross-account / cross-region control.

  # ----------------------------------------------------------------
  # DATABASE
  # ----------------------------------------------------------------
  # PostgreSQL database names cannot contain hyphens — use underscores.
  db_name  = replace("${local.name}_database", "-", "_")
  username = var.db_master_username
  port     = 5432

  # v7.0+ BREAKING CHANGE: `password` was removed.
  # Use write-only attributes instead. Bump password_wo_version
  # any time you rotate the password so Terraform knows to update it.
  password_wo         = var.db_master_password
  password_wo_version = 1

  # PROD: Let AWS manage the password:
  # manage_master_user_password = true
  # This stores it in Secrets Manager and enables auto-rotation.
  # Your app reads it at startup via the AWS SDK.

  # ----------------------------------------------------------------
  # NETWORK
  # ----------------------------------------------------------------
  db_subnet_group_name   = module.vpc.database_subnet_group_name
  vpc_security_group_ids = [aws_security_group.rds.id]

  # CRITICAL: No public access. The DB is in isolated subnets
  # with no internet route. This is belt AND suspenders.
  publicly_accessible = false

  # ----------------------------------------------------------------
  # HIGH AVAILABILITY
  # ----------------------------------------------------------------
  # Dev: Single-AZ. If it goes down, you wait.
  # PROD: Multi-AZ. AWS maintains a synchronous standby replica
  # in another AZ. Automatic failover in ~60-120 seconds.
  multi_az = false # PROD: true

  # ----------------------------------------------------------------
  # BACKUPS
  # ----------------------------------------------------------------
  backup_retention_period = 1 # Days. Minimum for dev.
  # PROD: Set to 7-35 days. Also enable:
  # - Point-in-time recovery (enabled by default with backups)
  # - Cross-region backup for disaster recovery
  backup_window = "03:00-04:00" # UTC. Pick your lowest-traffic window.

  # ----------------------------------------------------------------
  # MAINTENANCE
  # ----------------------------------------------------------------
  maintenance_window         = "Mon:04:00-Mon:05:00" # After backup window
  auto_minor_version_upgrade = true

  # Dev convenience: apply changes immediately instead of waiting
  # for the next maintenance window.
  apply_immediately = true # PROD: false (schedule changes during maintenance)

  # ----------------------------------------------------------------
  # DELETION PROTECTION
  # ----------------------------------------------------------------
  # Even in dev, this prevents accidental `terraform destroy` from
  # nuking your database. You'll have to manually disable it first.
  deletion_protection = false # PROD: true, absolutely non-negotiable

  # Skip final snapshot in dev (faster teardown).
  skip_final_snapshot = true # PROD: false
  # PROD: final_snapshot_identifier = "${local.name}-final-snapshot"

  # ----------------------------------------------------------------
  # PERFORMANCE INSIGHTS
  # ----------------------------------------------------------------
  # Free tier includes 7 days of retention. Shows you slow queries,
  # wait events, and which SQL is killing your CPU. Enable even in dev.
  performance_insights_enabled          = true
  performance_insights_retention_period = 7 # PROD: 731 (2 years, paid)

  # ----------------------------------------------------------------
  # CLOUDWATCH LOGS — export PG logs for easier debugging
  # ----------------------------------------------------------------
  enabled_cloudwatch_logs_exports = ["postgresql", "upgrade"]
  # "postgresql" = general/error logs. "upgrade" = useful during version bumps.
  # Free to export; you only pay for CloudWatch storage/ingestion.

  # ----------------------------------------------------------------
  # PARAMETER GROUP — Tuning PostgreSQL
  # ----------------------------------------------------------------
  # These override postgresql.conf defaults. The module creates a
  # parameter group for you.
  parameters = [
    {
      # Logs any query slower than 1 second. Essential for finding
      # N+1 queries your ORMs are generating.
      name  = "log_min_duration_statement"
      value = "1000"
    },
    {
      # Logs connections. Useful for catching connection leaks.
      name  = "log_connections"
      value = "1"
    },
    {
      # Log disconnections too — pairs with log_connections to
      # spot short-lived connections (connection churn).
      name  = "log_disconnections"
      value = "1"
    }
  ]
}
