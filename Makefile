SHELL:=/bin/bash
REQUIRED_BINARIES := kubectl cosign helm terraform kubectx kubecm ytt yq jq
WORKING_DIR := $(shell dirname $(realpath $(firstword $(MAKEFILE_LIST))))
BOOTSTRAP_DIR := ${WORKING_DIR}/bootstrap
TERRAFORM_DIR := ${WORKING_DIR}/terraform

HARVESTER_CONTEXT="harvester"
BASE_URL=mustafar.lol
GITEA_URL=git.$(BASE_URL)
GIT_ADMIN_PASSWORD="C4rb1De_S3cr4t"
CLOUDFLARE_TOKEN=""

# Carbide info
CARBIDE_USER="internal-tester-read"
CARBIDE_PASSWORD=""
IMAGES_FILE=""

# Registry info
REGISTRY_URL=harbor.$(BASE_URL)
REGISTRY_USER=admin
REGISTRY_PASSWORD=""

# Rancher on Harvester Info
RKE2_VIP=10.11.5.4
RANCHER_TARGET_NETWORK=services
RANCHER_URL=rancher.home.$(BASE_URL)
RANCHER_HA_MODE=true
RANCHER_WORKER_COUNT=1
RANCHER_NODE_SIZE="40Gi"
RANCHER_HARVESTER_WORKER_CPU_COUNT=2
RANCHER_HARVESTER_WORKER_MEMORY_SIZE="4Gi"
HARVESTER_RANCHER_CLUSTER_NAME=rancher-harvester
RKE2_IMAGE_NAME=ubuntu-rke2-airgap-harvester

check-tools: ## Check to make sure you have the right tools
	$(foreach exec,$(REQUIRED_BINARIES),\
		$(if $(shell which $(exec)),,$(error "'$(exec)' not found. It is a dependency for this Makefile")))
# certificate targets
# CloudDNS holder: kubectl create secret generic clouddns-dns01-solver-svc-acct --from-file=key.json
certs: check-tools # needs CLOUDFLARE_TOKEN set and HARVESTER_CONTEXT for non-default contexts
	@printf "\n===>Making Certificates\n";
	@kubectx $(HARVESTER_CONTEXT)
	@helm install cert-manager ${BOOTSTRAP_DIR}/rancher/cert-manager-v1.7.3.tgz \
    --namespace cert-manager \
	--create-namespace \
	--set installCRDs=true || true
	@ytt -f $(BOOTSTRAP_DIR)/certs/issuer-prod.yaml -f $(BOOTSTRAP_DIR)/certs/overlay-issuer.yaml -v api_token=$(CLOUDFLARE_TOKEN) | kubectl apply -f -
	@kubectl create ns harbor || true
	@ytt -f $(BOOTSTRAP_DIR)/certs/cert-harbor.yaml -v base_url=$(BASE_URL) | kubectl apply -f -
	@kubectl create ns git || true
	@ytt -f $(BOOTSTRAP_DIR)/certs/cert-gitea.yaml -v base_url=$(BASE_URL) | kubectl apply -f -
	@kubectl create ns cattle-system || true
	@ytt -f $(BOOTSTRAP_DIR)/certs/cert-rancher.yaml -v base_url=$(BASE_URL) | kubectl apply -f -
	@ytt -f $(BOOTSTRAP_DIR)/certs/cert-harvester.yaml -v base_url=$(BASE_URL) | kubectl apply -f -

certs-export: check-tools
	@printf "\n===>Exporting Certificates\n";
	@kubectx $(HARVESTER_CONTEXT)
	@kubectl get secret -n harbor harbor-prod-certificate -o yaml > harbor_cert.yaml
	@kubectl get secret -n git gitea-prod-certificate -o yaml > gitea_cert.yaml
	@kubectl get secret -n cattle-system rancher-airgap-certificate -o yaml > rancher_cert.yaml
	@kubectl get secret -n cattle-system harvester-homelab-certificate -o yaml > harvester_cert.yaml
certs-import: check-tools
	@printf "\n===>Importing Certificates\n";
	@kubectx $(HARVESTER_CONTEXT)
	@kubectl apply -f harbor_cert.yaml
	@kubectl apply -f gitea_cert.yaml
	@kubectl apply -f rancher_cert.yaml
	@kubectl apply -f harvester_cert.yaml

# registry targets
registry: check-tools
	@printf "\n===> Installing Registry\n";
	@kubectx $(HARVESTER_CONTEXT)
	@helm upgrade --install harbor ${BOOTSTRAP_DIR}/harbor/harbor-1.9.3.tgz \
	--version 1.9.3 -n harbor -f ${BOOTSTRAP_DIR}/harbor/values.yaml --create-namespace
registry-delete: check-tools
	@printf "\n===> Deleting Registry\n";
	@kubectx $(HARVESTER_CONTEXT)
	@helm delete harbor -n harbor

# airgap targets
pull-rancher: check-tools
	@printf "\n===>Pulling Rancher Images\n";
	@${BOOTSTRAP_DIR}/airgap_images/pull_carbide_rancher $(CARBIDE_USER) '$(CARBIDE_PASSWORD)'
	@printf "\nIf successful, your images will be available at /tmp/rancher-images.tar.gz and /tmp/cert-manager.tar.gz"
pull-misc: check-tools
	@printf "\n===>Pulling Misc Images\n";
	@${BOOTSTRAP_DIR}/airgap_images/pull_misc
push-images: check-tools
	@printf "\n===>Pushing Images to Harbor\n";
	@${BOOTSTRAP_DIR}/airgap_images/push_carbide $(REGISTRY_URL) $(REGISTRY_USER) '$(REGISTRY_PASSWORD)' $(IMAGES_FILE)

# git targets
git: check-tools
	@kubectx $(HARVESTER_CONTEXT)
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
	@kubectx $(HARVESTER_CONTEXT)
	@printf "\n===> Deleting Gitea\n";
	@helm delete gitea -n git

### terraform main targets
infra: check-tools
	@printf "\n=====> Terraforming Infra\n";
	$(MAKE) _terraform COMPONENT=infra

jumpbox: check-tools
	@printf "\n====> Terraforming Jumpbox\n";
	$(MAKE) _terraform COMPONENT=jumpbox
jumpbox-key: check-tools
	@printf "\n====> Grabbing generated SSH key\n";
	$(MAKE) _terraform-value COMPONENT=jumpbox FIELD=".jumpbox_ssh_key.value"
jumpbox-destroy: check-tools
	@printf "\n====> Destroying Jumpbox\n";
	$(MAKE) _terraform-destroy COMPONENT=jumpbox

rancher: check-tools  # state stored in Harvester K8S
	@printf "\n====> Terraforming RKE2 + Rancher\n";
	@kubecm delete $(HARVESTER_RANCHER_CLUSTER_NAME) || true
	@kubectx $(HARVESTER_CONTEXT)
	$(MAKE) _terraform COMPONENT=rancher VARS='TF_VAR_rancher_server_dns="$(RANCHER_URL)" TF_VAR_master_vip="$(RKE2_VIP)" TF_VAR_registry_url="$(REGISTRY_URL)" TF_VAR_worker_count=$(RANCHER_WORKER_COUNT) TF_VAR_control_plane_ha_mode=$(RANCHER_HA_MODE) TF_VAR_node_disk_size=$(RANCHER_NODE_SIZE) TF_VAR_worker_cpu_count=$(RANCHER_HARVESTER_WORKER_CPU_COUNT) TF_VAR_worker_memory_size=$(RANCHER_HARVESTER_WORKER_MEMORY_SIZE) TF_VAR_target_network_name=$(RANCHER_TARGET_NETWORK) TF_VAR_harvester_rke2_image_name=$(shell kubectl get virtualmachineimage -o yaml | yq e '.items[]|select(.spec.displayName=="$(RKE2_IMAGE_NAME)")' - | yq e '.metadata.name' -)'
	@cp ${TERRAFORM_DIR}/rancher/kube_config_server.yaml /tmp/$(HARVESTER_RANCHER_CLUSTER_NAME).yaml && kubecm add -c -f /tmp/$(HARVESTER_RANCHER_CLUSTER_NAME).yaml && rm /tmp/$(HARVESTER_RANCHER_CLUSTER_NAME).yaml
	@kubectx $(HARVESTER_RANCHER_CLUSTER_NAME)
rancher-destroy: check-tools
	@printf "\n====> Destroying RKE2 + Rancher\n";
	@kubectx $(HARVESTER_CONTEXT)
	$(MAKE) _terraform-destroy COMPONENT=rancher VARS='TF_VAR_target_network_name=$(RANCHER_TARGET_NETWORK) TF_VAR_harvester_rke2_image_name=$(shell kubectl get virtualmachineimage -o yaml | yq e '.items[]|select(.spec.displayName=="$(RKE2_IMAGE_NAME)")' - | yq e '.metadata.name' -)'
	@kubecm delete $(HARVESTER_RANCHER_CLUSTER_NAME) || true

# terraform sub-targets (don't use directly)
_terraform: check-tools
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) init
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) apply
_terraform-init: check-tools
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) init
_terraform-apply: check-tools
	@$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) apply
_terraform-value: check-tools
	@terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) output -json | jq -r '.jumpbox_ssh_key.value'
_terraform-destroy: check-tools
	$(VARS) terraform -chdir=${TERRAFORM_DIR}/$(COMPONENT) destroy