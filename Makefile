SHELL:=/bin/bash
REQUIRED_BINARIES := kubectl cosign helm terraform kubectx kubecm
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell git rev-parse --show-toplevel)
BOOTSTRAP_DIR := ${WORKING_DIR}/bootstrap
TERRAFORM_DIR := ${WORKING_DIR}/terraform

EL8000_CONTEXT="harvester"
LOCAL_CLUSTER_NAME=rancher-aws
BASE_URL=homelab.platformfeverdream.io
GITEA_URL=git.$(BASE_URL)
HARBOR_CA_CERT=/tmp/harbor.ca.crt
GIT_ADMIN_PASSWORD="Pa22word"

# Carbide info
CARBIDE_USER="internal-tester-read"
CARBIDE_PASSWORD=""
IMAGES_FILE=""

# Harbor info
HARBOR_URL=harbor.$(BASE_URL)
HARBOR_USER=admin
HARBOR_PASSWORD=""

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile")))
# certificate targets
certs: check-tools
	@printf "\n===>Making Certificates\n";
	@kubectx $(EL8000_CONTEXT)
	@helm install cert-manager ${BOOTSTRAP_DIR}/rancher/cert-manager-v1.7.3.tgz \
    --namespace cert-manager \
	--create-namespace \
	--set installCRDs=true || true
	@kubectl apply -f $(BOOTSTRAP_DIR)/certs/issuer-prod.yaml
	@kubectl create ns harbor || true
	@kubectl apply -f $(BOOTSTRAP_DIR)/certs/cert-harbor.yaml
	@kubectl create ns git || true
	@kubectl apply -f $(BOOTSTRAP_DIR)/certs/cert-gitea.yaml
	@kubectl create ns cattle-system || true
	@kubectl apply -f $(BOOTSTRAP_DIR)/certs/cert-rancher.yaml
	@kubectl apply -f $(BOOTSTRAP_DIR)/certs/cert-harvester.yaml

certs-export: check-tools
	@printf "\n===>Fetching Certificates\n";
	@kubectx $(EL8000_CONTEXT)
	@kubectl get secret -n harbor harbor-prod-certificate -o yaml > harbor_cert.yaml
	@kubectl get secret -n git gitea-prod-certificate -o yaml > gitea_cert.yaml
	@kubectl get secret -n cattle-system rancher-airgap-certificate -o yaml > rancher_cert.yaml
	@kubectl get secret -n cattle-system harvester-homelab-certificate -o yaml > harvester_cert.yaml

# registry targets
registry: check-tools
	@printf "\n===> Installing Registry\n";
	@kubectx $(EL8000_CONTEXT)
	@helm install harbor ${BOOTSTRAP_DIR}/harbor/harbor-1.9.3.tgz \
	--version 1.9.3 -n harbor -f ${BOOTSTRAP_DIR}/harbor/values.yaml --create-namespace

registry-delete: check-tools
	@printf "\n===> Deleting Registry\n";
	@helm delete harbor -n harbor

# airgap targets
pull-rke2: check-tools
	@printf "\n===>Pulling RKE2 Images\n";
	@${BOOTSTRAP_DIR}/airgap_images/pull_carbide_rke2 $(CARBIDE_USER) '$(CARBIDE_PASSWORD)'
	@printf "\nIf successful, your images will be available at /tmp/rke2-images.tar.gz"
pull-rancher: check-tools
	@printf "\n===>Pulling Rancher Images\n";
	@${BOOTSTRAP_DIR}/airgap_images/pull_carbide_rancher $(CARBIDE_USER) '$(CARBIDE_PASSWORD)'
	@printf "\nIf successful, your images will be available at /tmp/rancher-images.tar.gz and /tmp/cert-manager.tar.gz"
push-images: check-tools
	@printf "\n===>Pushing Images to Harbor\n";
	@${BOOTSTRAP_DIR}/airgap_images/push_carbide $(HARBOR_URL) $(HARBOR_USER) '$(HARBOR_PASSWORD)' $(IMAGES_FILE)

# git targets
git: check-tools
	@kubectl create ns git || true
	@kubectl apply -f ${BOOTSTRAP_DIR}/certs/cert-gitea.yaml || true
	@helm install gitea $(BOOTSTRAP_DIR)/gitea/gitea-6.0.1.tgz \
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
	
