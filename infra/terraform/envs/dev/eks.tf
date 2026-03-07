module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.15"

  name               = "${local.name}-eks"
  kubernetes_version = var.cluster_version

  # NETWORKING
  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets
  # Nodes go in private subnets. Always. No exceptions.
  # The control plane ENIs also go here for kubectl communication.

  # CLUSTER ENDPOINT ACCESS
  # This controls who can reach the Kubernetes API server.
  #
  # Dev: Public + Private. You need public to run kubectl from your
  # laptop. Private so pods inside VPC can reach the API server
  # without leaving the network.
  #
  # PROD: Set cluster_endpoint_public_access = false
  # Access the cluster only via VPN/bastion/SSM. This closes the
  # single biggest attack surface on your cluster.

  endpoint_public_access  = true # PROD: false
  endpoint_private_access = true

  # PROD: If keeping public access, lock it to your office IP:
  # cluster_endpoint_public_access_cidrs = ["203.0.113.0/24"]

  # CONTROL PLANE LOGGING — enable even in dev
  # These go to CloudWatch. Invaluable for debugging auth issues,
  # scheduler decisions, and audit trails. Free to enable (you pay
  # for CloudWatch ingestion/storage, but it's minimal in dev).
  enabled_log_types = ["api", "audit", "authenticator"]
  # PROD: Add "controllerManager" and "scheduler" too.
  # Full list: ["api", "audit", "authenticator", "controllerManager", "scheduler"]

  # CLUSTER ADDONS
  # These are AWS-managed. They auto-update and are tightly
  # integrated. Don't install these via Helm yourself.

  addons = {
    # VPC CNI: Assigns real VPC IPs to pods. This is why we need
    # big subnets. Alternative (Calico overlay) breaks some AWS
    # integrations like security groups for pods.
    vpc-cni = {
      most_recent    = true
      before_compute = true
      # PROD: Enable prefix delegation for higher pod density:
      # configuration_values = jsonencode({
      #   env = { ENABLE_PREFIX_DELEGATION = "true" }
      # })
      # This lets one ENI IP serve 16 pods instead of 1.
    }

    # CoreDNS: Cluster-internal DNS. Your services find each other
    # via <service>.<namespace>.svc.cluster.local
    coredns = {
      most_recent = true
    }

    # kube-proxy: Handles Service → Pod routing via iptables/IPVS.
    kube-proxy = {
      most_recent    = true
      before_compute = true
    }

    # EBS CSI Driver: Required for PersistentVolumes backed by EBS.
    # Your microservices probably use stateless pods, but things like
    # Kafka, monitoring (Prometheus), or logging need storage.
    aws-ebs-csi-driver = {
      most_recent              = true
      service_account_role_arn = module.ebs_csi_irsa.arn
    }
  }

  # NODE GROUPS
  # Managed Node Groups = AWS handles the EC2 lifecycle (launch,
  # drain, terminate on update). You don't SSH into these. Ever.
  #
  # We're using a single "general" group for dev.
  # PROD: Split into:
  #   - "system" group: CoreDNS, monitoring, ingress controllers
  #   - "app" group: Your microservices (use spot for cost saving)
  #   - "compute" group: CPU-intensive stuff (route optimization, etc.)

  eks_managed_node_groups = {
    general = {
      # INSTANCE TYPES
      # t3.medium: 2 vCPU, 4 GB RAM, burstable.
      # Fine for dev. Each can host ~17 pods (ENI limit).
      #
      # PROD: Use m6i.large or m7i.large (non-burstable).
      # Burstable instances (t3) will throttle under sustained load.
      # Also add spot instances for non-critical workloads:
      #   instance_types = ["m6i.large", "m6i.xlarge", "m5.large"]
      #   capacity_type  = "SPOT"

      instance_types = ["t3.medium"]
      capacity_type  = "ON_DEMAND"

      # AMI TYPE — use AL2023 (AL2 is deprecated from K8s 1.33+)
      ami_type = "AL2023_x86_64_STANDARD"
      # AL2023 uses cgroup v2 by default, which aligns with K8s 1.35+
      # that deprecates cgroup v1. This avoids future breakage.

      # SCALING
      # Dev: 2 nodes (one per AZ for basic resilience testing).
      # max_size is higher so Cluster Autoscaler can work.
      #
      # PROD: min_size = 3 (one per AZ), desired = 5-6,
      # max_size = 20+. Also deploy Karpenter instead of Cluster
      # Autoscaler — it's faster and smarter about right-sizing.

      min_size     = 1
      max_size     = 4
      desired_size = 2

      # DISK
      disk_size = 50 # GB. Default 20 is too small for container images.

      # Labels let you control pod placement with nodeSelector
      labels = {
        role        = "general"
        environment = "dev"
      }
    }
  }

  # AUTHENTICATION: Who can access the cluster?
  # The module manages aws-auth ConfigMap. This maps IAM → K8s RBAC.
  #
  # enable_cluster_creator_admin_permissions gives YOUR IAM user/role
  # (the one running terraform apply) full cluster-admin. Without
  # this, you'd lock yourself out of your own cluster.

  enable_cluster_creator_admin_permissions = true

  # Grant the CI plan role read access to the cluster so that
  # terraform plan can refresh kubernetes/helm resource state.
  access_entries = {
    ci_plan = {
      principal_arn = "arn:aws:iam::129580962636:role/github-actions-terraform-plan-role"
      policy_associations = {
        cluster_admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
    valeedyounas = {
      principal_arn = "arn:aws:iam::129580962636:user/valeedyounas"
      policy_associations = {
        cluster_admin = {
          policy_arn   = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"
          access_scope = { type = "cluster" }
        }
      }
    }
  }

  # PROD: Use access entries for team members:
  # access_entries = {
  #   devs = {
  #     principal_arn = "arn:aws:iam::role/DevTeamRole"
  #     policy_associations = {
  #       dev = {
  #         policy_arn = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSViewPolicy"
  #         access_scope = { type = "namespace", namespaces = ["mvaleed-platform"] }
  #       }
  #     }
  #   }
  # }
}

# IRSA for EBS CSI Driver
# IRSA = IAM Roles for Service Accounts. This lets a K8s service
# account assume an IAM role — no access keys floating around.
# The EBS CSI driver needs IAM permissions to create/attach EBS volumes.
#
# UPGRADE NOTE (IAM module v6.x):
#   Submodule renamed: iam-role-for-service-accounts-eks → iam-role-for-service-accounts
#   `role_name` renamed to `name`
#   Output `iam_role_arn` renamed to `arn`
#   Consider migrating to EKS Pod Identity for new clusters.

module "ebs_csi_irsa" {
  source  = "terraform-aws-modules/iam/aws//modules/iam-role-for-service-accounts"
  version = "~> 6.4"

  name                  = "${local.name}-ebs-csi"
  attach_ebs_csi_policy = true

  oidc_providers = {
    main = {
      provider_arn               = module.eks.oidc_provider_arn
      namespace_service_accounts = ["kube-system:ebs-csi-controller-sa"]
    }
  }
}
