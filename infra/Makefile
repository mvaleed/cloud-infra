# ──────────────────────────────────────────────────────────────────
# Infrastructure Makefile
# ──────────────────────────────────────────────────────────────────
# Terraform:
#   make plan-dev      — terraform plan for dev
#   make apply-dev     — terraform apply for dev
#   make destroy-dev   — full teardown of dev (zero cost)
#
# Kubernetes:
#   make k8s-apply-dev — apply base manifests + create RDS secret for dev
#   make k8s-diff-dev  — dry-run diff against live cluster
# ──────────────────────────────────────────────────────────────────

SHELL := /bin/bash
.PHONY: plan-dev apply-dev destroy-dev \
        k8s-apply-dev k8s-diff-dev \
        _tf-init-dev _k8s-outputs-dev

# ══════════════════════════════════════════════════════════════════
# Terraform
# ══════════════════════════════════════════════════════════════════

TF_DEV_DIR  := terraform/envs/dev
TF_DEV_VARS := -var-file=dev.tfvars

_tf-init-dev:
	@echo "══════════════════════════════════════════════"
	@echo "  Initializing Terraform — dev"
	@echo "══════════════════════════════════════════════"
	cd $(TF_DEV_DIR) && terraform init -input=false

plan-dev: _tf-init-dev
	@echo "══════════════════════════════════════════════"
	@echo "  Terraform Plan — dev"
	@echo "══════════════════════════════════════════════"
	cd $(TF_DEV_DIR) && terraform plan -input=false $(TF_DEV_VARS)

apply-dev: _tf-init-dev
	@echo "══════════════════════════════════════════════"
	@echo "  Terraform Apply — dev"
	@echo "══════════════════════════════════════════════"
	cd $(TF_DEV_DIR) && terraform apply -input=false $(TF_DEV_VARS)

# ── Destroy ───────────────────────────────────────────────────────
# Full teardown. Disables RDS deletion protection first, then
# destroys everything. Verifies empty state at the end.
# ──────────────────────────────────────────────────────────────────
destroy-dev: _tf-init-dev
	@echo "══════════════════════════════════════════════"
	@echo "  DESTROYING dev environment"
	@echo "══════════════════════════════════════════════"
	@echo ""
	@echo ">>> Step 1: Disabling RDS deletion protection (if enabled)..."
	@cd $(TF_DEV_DIR) && \
	if terraform state list 2>/dev/null | grep -q 'module.rds'; then \
		echo "    RDS found in state — applying with deletion_protection=false..."; \
		terraform apply -input=false -auto-approve \
			-target=module.rds \
			$(TF_DEV_VARS) \
			2>/dev/null || true; \
	else \
		echo "    No RDS found in state — skipping."; \
	fi
	@echo ""
	@echo ">>> Step 2: Destroying all resources..."
	cd $(TF_DEV_DIR) && terraform destroy -input=false $(TF_DEV_VARS)
	@echo ""
	@echo ">>> Step 3: Verifying clean state..."
	@cd $(TF_DEV_DIR) && \
	REMAINING=$$(terraform state list 2>/dev/null | wc -l | tr -d ' '); \
	if [ "$$REMAINING" -eq 0 ]; then \
		echo "  State is empty. All resources destroyed. Cost = $$""0."; \
	else \
		echo "  WARNING: $$REMAINING resource(s) still in state!"; \
		terraform state list; \
		echo "  Run 'make destroy-dev' again or investigate manually."; \
		exit 1; \
	fi

# ══════════════════════════════════════════════════════════════════
# Kubernetes
# ══════════════════════════════════════════════════════════════════
# Workflow:
#   1. Fetch Terraform outputs (RDS endpoint, DB name, username)
#   2. Apply manifests via kubectl (namespace, etc.)
#   3. Create RDS secret imperatively via kubectl (no secrets on disk)
#
# Prerequisites:
#   - kubectl configured (aws eks update-kubeconfig)
#   - TF_VAR_DB_MASTER_PASSWORD or RDS_PASSWORD env var set
#   - Terraform already applied (outputs must exist)
# ──────────────────────────────────────────────────────────────────

K8S_DIR := k8s

# Fetch Terraform outputs and validate prerequisites
_k8s-outputs-dev: _tf-init-dev
	@echo "══════════════════════════════════════════════"
	@echo "  Reading Terraform outputs — dev"
	@echo "══════════════════════════════════════════════"
	@# Fetch Terraform outputs
	$(eval RDS_ENDPOINT := $(shell cd $(TF_DEV_DIR) && terraform output -raw rds_endpoint 2>/dev/null))
	$(eval RDS_HOST := $(shell echo "$(RDS_ENDPOINT)" | cut -d: -f1))
	$(eval RDS_PORT := $(shell echo "$(RDS_ENDPOINT)" | cut -d: -f2))
	$(eval RDS_DATABASE := $(shell cd $(TF_DEV_DIR) && terraform output -raw rds_database_name 2>/dev/null))
	$(eval RDS_USERNAME := $(shell cd $(TF_DEV_DIR) && terraform output -raw rds_master_username 2>/dev/null))
	@if [ -z "$(RDS_HOST)" ]; then \
		echo "ERROR: Could not read Terraform outputs. Run 'make apply-dev' first."; \
		exit 1; \
	fi
	@# RDS_PASSWORD comes from env (set via TF_VAR_db_master_password or RDS_PASSWORD)
	$(eval RDS_PASSWORD := $(or $(RDS_PASSWORD),$(TF_VAR_db_master_password)))
	@if [ -z "$(RDS_PASSWORD)" ]; then \
		echo "ERROR: RDS_PASSWORD or TF_VAR_db_master_password env var must be set."; \
		exit 1; \
	fi

k8s-diff-dev: _k8s-outputs-dev
	@echo "══════════════════════════════════════════════"
	@echo "  K8s Diff — dev"
	@echo "══════════════════════════════════════════════"
	@# Diff manifests
	kubectl diff -f $(K8S_DIR)/ || true
	@# Diff the secret
	kubectl create secret generic rds-credentials \
		--namespace=mvaleed-platform \
		--from-literal=DB_HOST="$(RDS_HOST)" \
		--from-literal=DB_PORT="$(RDS_PORT)" \
		--from-literal=DB_NAME="$(RDS_DATABASE)" \
		--from-literal=DB_USERNAME="$(RDS_USERNAME)" \
		--from-literal=DB_PASSWORD="$(RDS_PASSWORD)" \
		--from-literal=DATABASE_URL="postgresql://$(RDS_USERNAME):$(RDS_PASSWORD)@$(RDS_HOST):$(RDS_PORT)/$(RDS_DATABASE)" \
		--dry-run=client -o yaml | kubectl diff -f - || true

k8s-apply-dev: _k8s-outputs-dev
	@echo "══════════════════════════════════════════════"
	@echo "  K8s Apply — dev"
	@echo "══════════════════════════════════════════════"
	@# Apply manifests (namespace, etc.)
	kubectl apply -f $(K8S_DIR)/
	@# Create secret imperatively (no secrets written to disk)
	kubectl create secret generic rds-credentials \
		--namespace=mvaleed-platform \
		--from-literal=DB_HOST="$(RDS_HOST)" \
		--from-literal=DB_PORT="$(RDS_PORT)" \
		--from-literal=DB_NAME="$(RDS_DATABASE)" \
		--from-literal=DB_USERNAME="$(RDS_USERNAME)" \
		--from-literal=DB_PASSWORD="$(RDS_PASSWORD)" \
		--from-literal=DATABASE_URL="postgresql://$(RDS_USERNAME):$(RDS_PASSWORD)@$(RDS_HOST):$(RDS_PORT)/$(RDS_DATABASE)" \
		--dry-run=client -o yaml | kubectl apply -f -
	@echo ""
	@echo "  Manifests and secret applied."
