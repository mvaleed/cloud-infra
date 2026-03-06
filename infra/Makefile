SHELL := /bin/bash
.PHONY: plan-dev apply-dev destroy-dev \
        _tf-init-dev

TF_DEV_DIR  := terraform/envs/dev
TF_DEV_VARS := -var-file=dev.tfvars

_tf-init-dev:
	cd $(TF_DEV_DIR) && terraform init -input=false

plan-dev: _tf-init-dev
	cd $(TF_DEV_DIR) && terraform plan -input=false $(TF_DEV_VARS)

apply-dev: _tf-init-dev
	cd $(TF_DEV_DIR) && terraform apply -input=false $(TF_DEV_VARS)

destroy-dev: _tf-init-dev
	cd $(TF_DEV_DIR) && terraform destroy -input=false $(TF_DEV_VARS)
