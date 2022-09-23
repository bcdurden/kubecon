SHELL:=/bin/bash
REQUIRED_BINARIES := kubectl
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell git rev-parse --show-toplevel)
BOOTSTRAP_DIR := ${WORKING_DIR}/bootstrap
TERRAFORM_DIR := ${WORKING_DIR}/terraform

EL8000_CONTEXT="harvester"
LOCAL_CLUSTER_NAME=rancher-aws
BASE_URL=homelab.platformfeverdream.io
HARBOR_URL=harbor.$(BASE_URL)
GITEA_URL=git.$(BASE_URL)
HARBOR_CA_CERT=/tmp/harbor.ca.crt
GIT_ADMIN_PASSWORD="Pa22word"

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile")))

# registry targets
registry: check-tools
	@printf "\n===> Installing Registry\n";
	@kubectx $(EL8000_CONTEXT)
	@kubectl create ns harbor || true
	@kubectl apply -f ${BOOTSTRAP_DIR}/rancher/cert-manager-crd.yaml
	@helm install cert-manager ${BOOTSTRAP_DIR}/rancher/cert-manager-v1.7.1.tgz \
    --namespace cert-manager \
	--create-namespace
	@kubectl apply -f ${BOOTSTRAP_DIR}/harbor/issuer-prod.yaml
	@kubectl apply -f ${BOOTSTRAP_DIR}/harbor/cert.yaml
	@pushd bootstrap/harbor && helm install harbor ${BOOTSTRAP_DIR}/harbor/harbor-1.9.3.tgz \
	--version 1.9.3 -n harbor -f values.yaml && popd

registry-delete: check-tools
	@printf "\n===> Deleting Registry\n";
	@helm delete harbor -n harbor

registry-cert: check-tools
	@printf "\n===>Fetching Harbor CA Certificate\n";
	@kubectx harvester
	@helm status harbor -n harbor > /dev/null
	@kubectl get secret harbor-ingress -n harbor -o yaml | yq e '.data."ca.crt"' - | base64 -d > $(HARBOR_CA_CERT)
	@cat $(HARBOR_CA_CERT)

# git targets
git: check-tools
	@kubectl create ns git || true
	@kubectl apply -f ${BOOTSTRAP_DIR}/gitea/cert.yaml
	@helm upgrade gitea $(BOOTSTRAP_DIR)/gitea/gitea-6.0.1.tgz \
	--namespace git \
	--set gitea.admin.password=$(GIT_ADMIN_PASSWORD) \
	--set gitea.admin.username=gitea \
	--set persistence.size=10Gi \
	--set postgresql.persistence.size=1Gi \
	--set gitea.config.server.ROOT_URL=https://$(GITEA_URL) \
	--set gitea.config.server.DOMAIN=$(GITEA_URL) \
	--set gitea.config.server.PROTOCOL=http \
	-f $(BOOTSTRAP_DIR)/gitea/values.yaml

# terraform targets
terraform: check-tools
	@kubectx $(EL8000_CONTEXT)
	@terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) init
	@terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) apply
terraform-destroy: check-tools
	@kubectx $(EL8000_CONTEXT)
	@terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) init
	@terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) destroy

infra: check-tools
	@printf "\n=====> Terraforming Infra\n";
	$(MAKE) terraform COMPONENT=infra

jumpbox: check-tools
	@printf "\n====> Terraforming Jumpbox\n";
	$(MAKE) terraform COMPONENT=jumpbox
jumpbox-destroy: check-tools
	@printf "\n====> Destroying Jumpbox\n";
	$(MAKE) terraform-destroy COMPONENT=jumpbox

rancher: check-tools
	@printf "\n====> Terraforming RKE2 + Rancher\n";
	@kubectx $(EL8000_CONTEXT)
	$(MAKE) terraform COMPONENT=rancher
	@cp ${TERRAFORM_DIR}/rancher/kube_config_server.yaml /tmp/rancher-el8000.yaml && kubecm add -f /tmp/rancher-el8000.yaml && rm /tmp/rancher-el8000.yaml
rancher-destroy: check-tools
	@printf "\n====> Terraforming RKE2 + Rancher\n";
	$(MAKE) terraform-destroy COMPONENT=rancher
	