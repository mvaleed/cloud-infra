resource "kubernetes_namespace" "platform" {
  metadata {
    name = var.project_name # "mvaleed-platform"
    labels = {
      "app.kubernetes.io/managed-by" = "terraform"
      "environment"                  = var.environment
    }
  }
  depends_on = [module.eks]
}

resource "kubernetes_secret" "rds_credentials" {
  metadata {
    name      = "rds-credentials"
    namespace = kubernetes_namespace.platform.metadata[0].name
  }

  data = {
    DB_HOST      = split(":", module.rds.db_instance_endpoint)[0]
    DB_PORT      = split(":", module.rds.db_instance_endpoint)[1]
    DB_NAME      = module.rds.db_instance_name
    DB_USERNAME  = var.db_master_username
    DB_PASSWORD  = var.db_master_password
    DATABASE_URL = "postgresql://${var.db_master_username}:${var.db_master_password}@${module.rds.db_instance_endpoint}/${module.rds.db_instance_name}"
  }
}

resource "helm_release" "traefik" {
  name             = "traefik"
  repository       = "https://traefik.github.io/charts"
  chart            = "traefik"
  version          = "39.0.4"
  namespace        = "traefik"
  create_namespace = true
  atomic           = true
  timeout          = 300 # 5 min timeout for NLB provisioning

  values = [yamlencode({
    service = {
      type = "LoadBalancer"
      annotations = {
        "service.beta.kubernetes.io/aws-load-balancer-type"            = "external"
        "service.beta.kubernetes.io/aws-load-balancer-nlb-target-type" = "ip"
        "service.beta.kubernetes.io/aws-load-balancer-scheme"          = "internet-facing"
      }
    }

    ports = {
      web = {
        port        = 8000
        exposedPort = 80
        protocol    = "TCP"
      }
      websecure = {
        port        = 8443
        exposedPort = 443
        protocol    = "TCP"
      }
    }

    ingressRoute = {
      dashboard = {
        enabled = false # Don't expose dashboard to internet
      }
    }

    resources = {
      requests = { cpu = "100m", memory = "128Mi" }
      limits   = { cpu = "300m", memory = "256Mi" }
    }

    logs = {
      general = { level = "INFO" }
      access  = { enabled = true }
    }
  })]

  depends_on = [module.eks]
}

resource "helm_release" "cert_manager" {
  name             = "cert-manager"
  repository       = "https://charts.jetstack.io"
  chart            = "cert-manager"
  version          = "v1.19.4"
  namespace        = "cert-manager"
  create_namespace = true
  atomic           = true
  timeout          = 300

  set {
    name  = "crds.enabled"
    value = "true"
  }

  values = [yamlencode({
    resources = {
      requests = { cpu = "50m", memory = "64Mi" }
      limits   = { cpu = "200m", memory = "128Mi" }
    }
  })]

  depends_on = [module.eks]
}

resource "kubernetes_manifest" "letsencrypt_staging" {
  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = "letsencrypt-staging"
    }
    spec = {
      acme = {
        # Staging endpoint: won't issue browser-trusted certs but has
        # generous rate limits for testing. Switch to production when ready:
        # server = "https://acme-v02.api.letsencrypt.org/directory"
        server = "https://acme-staging-v02.api.letsencrypt.org/directory"
        email  = "admin@example.com" # TODO: Change to your real email
        privateKeySecretRef = {
          name = "letsencrypt-staging-key"
        }
        solvers = [{
          http01 = {
            ingress = {
              ingressTemplate = {
                metadata = {
                  annotations = {
                    "kubernetes.io/ingress.class" = "traefik"
                  }
                }
              }
            }
          }
        }]
      }
    }
  }

  depends_on = [helm_release.cert_manager, helm_release.traefik]
}

data "kubernetes_service" "traefik" {
  metadata {
    name      = "traefik"
    namespace = helm_release.traefik.namespace
  }

  depends_on = [helm_release.traefik]
}
