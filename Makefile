SHELL:=/bin/bash
REQUIRED_BINARIES := kubectl cosign helm terraform kubectx kubecm ytt yq jq
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
ROOT_DIR := $(shell git rev-parse --show-toplevel)
BOOTSTRAP_DIR := ${WORKING_DIR}/bootstrap
TERRAFORM_DIR := ${WORKING_DIR}/terraform

EL8000_CONTEXT="harvester"
BASE_URL=mustafar.lol
GITEA_URL=git.$(BASE_URL)
HARBOR_CA_CERT=/tmp/harbor.ca.crt
GIT_ADMIN_PASSWORD=""
CLOUDFLARE_TOKEN=""

# Carbide info
CARBIDE_USER="internal-tester-read"
CARBIDE_PASSWORD=""
IMAGES_FILE=""

# Harbor info
HARBOR_URL=harbor.$(BASE_URL)
HARBOR_USER=admin
HARBOR_PASSWORD=""

# Rancher Info
RKE2_VIP=10.11.5.4
RANCHER_URL=rancher.$(BASE_URL)
RANCHER_HA_MODE=false
RANCHER_WORKER_COUNT=2
RANCHER_NODE_SIZE="20Gi"

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile")))
# certificate targets
certs: check-tools # needs CLOUDFLARE_TOKEN set and EL8000_CONTEXT for non-default contexts
	@printf "\n===>Making Certificates\n";
	@kubectx $(EL8000_CONTEXT)
	@helm install cert-manager ${BOOTSTRAP_DIR}/rancher/cert-manager-v1.7.3.tgz \
    --namespace cert-manager \
	--create-namespace \
	--set installCRDs=true || true
	@ytt -f $(BOOTSTRAP_DIR)/certs/issuer-prod.yaml -f $(BOOTSTRAP_DIR)/certs/overlay-issuer.yaml -v api_token=$(CLOUDFLARE_TOKEN) | kubectl apply -f -
	@kubectl create ns harbor || true
	@kubectl apply -f $(BOOTSTRAP_DIR)/certs/cert-harbor.yaml
	@kubectl create ns git || true
	@kubectl apply -f $(BOOTSTRAP_DIR)/certs/cert-gitea.yaml
	@kubectl create ns cattle-system || true
	@kubectl apply -f $(BOOTSTRAP_DIR)/certs/cert-rancher.yaml
	@kubectl apply -f $(BOOTSTRAP_DIR)/certs/cert-harvester.yaml

certs-export: check-tools
	@printf "\n===>Exporting Certificates\n";
	@kubectx $(EL8000_CONTEXT)
	@kubectl get secret -n harbor harbor-prod-certificate -o yaml > harbor_cert.yaml
	@kubectl get secret -n git gitea-prod-certificate -o yaml > gitea_cert.yaml
	@kubectl get secret -n cattle-system rancher-airgap-certificate -o yaml > rancher_cert.yaml
	@kubectl get secret -n cattle-system harvester-homelab-certificate -o yaml > harvester_cert.yaml
certs-import: check-tools
	@printf "\n===>Importing Certificates\n";
	@kubectx $(EL8000_CONTEXT)
	@kubectl apply -f harbor_cert.yaml
	@kubectl apply -f gitea_cert.yaml
	@kubectl apply -f rancher_cert.yaml
	@kubectl apply -f harvester_cert.yaml

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
pull-misc: check-tools
	@printf "\n===>Pulling Misc Images\n";
	@${BOOTSTRAP_DIR}/airgap_images/pull_misc
push-images: check-tools
	@printf "\n===>Pushing Images to Harbor\n";
	@${BOOTSTRAP_DIR}/airgap_images/push_carbide $(HARBOR_URL) $(HARBOR_USER) '$(HARBOR_PASSWORD)' $(IMAGES_FILE)

# git targets
git: check-tools
	@kubectx $(EL8000_CONTEXT)
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
git-delete: check-tools
	@kubectx $(EL8000_CONTEXT)
	@printf "\n===> Deleting Gitea\n";
	@helm delete gitea -n git

# terraform targets
terraform: check-tools
	@kubectx $(EL8000_CONTEXT)
	@terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) init
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) apply
terraform-value: check-tools
	@kubectx $(EL8000_CONTEXT)
	@terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) output -json | jq -r '.jumpbox_ssh_key.value'
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
jumpbox-key: check-tools
	@printf "\n====> Grabbing generated SSH key\n";
	$(MAKE) terraform-value COMPONENT=jumpbox FIELD=".jumpbox_ssh_key.value"
jumpbox-destroy: check-tools
	@printf "\n====> Destroying Jumpbox\n";
	$(MAKE) terraform-destroy COMPONENT=jumpbox

rancher: check-tools
	@printf "\n====> Terraforming RKE2 + Rancher\n";
	@kubectx $(EL8000_CONTEXT)
	$(MAKE) terraform COMPONENT=rancher VARS='TF_VAR_rancher_server_dns="$(RANCHER_URL)" TF_VAR_master_vip="$(RKE2_VIP)" TF_VAR_harbor_url="$(HARBOR_URL)" TF_VAR_worker_count=$(RANCHER_WORKER_COUNT) TF_VAR_control_plane_ha_mode=$(RANCHER_HA_MODE) TF_VAR_node_disk_size=$(RANCHER_NODE_SIZE)'
	@cp ${TERRAFORM_DIR}/rancher/kube_config_server.yaml /tmp/rancher-el8000.yaml && kubecm add -c -f /tmp/rancher-el8000.yaml && rm /tmp/rancher-el8000.yaml
	@kubectl get secret -n cattle-system tls-rancher-ingress -o yaml > rancher_cert.yaml
	@kubectx rancher-el8000
	@kubectl apply -f rancher_cert.yaml
	@rm rancher_cert.yaml
	@kubectx $(EL8000_CONTEXT)
rancher-destroy: check-tools
	@printf "\n====> Destroying RKE2 + Rancher\n";
	$(MAKE) terraform-destroy COMPONENT=rancher
	@kubecm delete rancher-el8000
