# Kubecon Infrastructure Demo
This document will contain a basic explanation of how to utilize them demo and some of the ideas it represents. This document assumes the user is proficient with Harbor and can configure the external networking stack to accomodate. 

## Required Tools
kubectl cosign helm terraform kubectx kubecm ytt yq jq

# TOC

# Demo Equipment List
* EL8000
* Network Switch
* OpenWRT device for routing/wifi needs
* Laptop with Wifi used for bootstrapping
* Any wifi devices to be used for viewing dashboards

# Full-Stack Definition

# Installation
TBD: Harvester Installation on EL8000, cover iso image hosting and ILO operation
TBD: Cover turning Longhorn's 12% resource request down

## Harvester Kubeconfig
This demo makes use of Harvester as a singleton K8S cluster in order to provide infrastrcture-based services such as code and image stores. Download the kubeconfig from the Harvester UI console in the `Support` section. Once downloaded, you can use `kubecm` to merge the downloaded kubeconfig with your main kubeconfig. It's important to set the name of the context to something that can be represented as a simple string. I used `harvester` as it was simple and straight-forward.

## Concepts

## Network Configuration Considerations
Harvester utilizes VLANs to map networks to VMs and this implementation requires DHCP CIDR ranges per VLAN. Due to how network traffic will flow and how DHCP traffic may be queried, a hardware-based or more real-time based solution is required. 

A VM to manage DHCP and VLAN traffic exeternally is not going to be capable of handling the amount of traffic necessary. Harvester does not use VLANs for hardware-based network separation but does require the upstream switch/router solution to allow traffic to pass. 

It's best to configure open traffic between VLANs with firewall rules. In a more production environment, we'd lock things down further where VLANs 6-8 could not communicate with each other as well as define a LoadBalancing VIP pool on another VLAN entirely.

### VLANs and DHCP
Underhood, Harvester relies on the networking stack to trunk VLANs in hybrid mode. It is also greatly preferred to have DHCP per VLAN with different cidr ranges for network separation. Configure your DHCP servers to listen on appropriate VLANs and provide DHCP addresses in the ranges specified below:

|Name 	|VLAN 	|CIDR 	|DHCP Range   	| Total Dynamic IPs  	|
|---	|---	|---	|---	|---	|
|Management   	|-   	|10.11.0.0/24   	|10.11.0.50-254   	|204   	|
|Services   	|5   	|10.11.5.0/24   	|10.11.5.50-254   	|204   	|
|Sandbox   	|6   	|10.11.16.0/20   	|10.11.16.50-10.11.31.254   	|4044   	|
|Dev   	|7   	|10.11.32.0/20   	|10.11.32.50-10.11.47.254   	|4044   	|
|Prod   	|8   	|10.11.48.0/20   	|10.11.48.50-10.11.63.254   	|4044   	|


## Harvester Configuration
When configuring the EL8000 Harvester installation, there are a few key configuration items that need to happen. The EL8000 is a 4-node device and each node will need to have the correct configuration.
* Each Harvester node should use a static VIP (the last step of configuration) in the `10.11.0.4-50` range
* Each Harvester node should have the management NIC defined using the 1Gbps interface
* Each Harvester node should have the vlan network NIC defined using a 10Gbps interface
* There's a possibility that private X509 self-signed certs become a problem, certs have been generated or can be generated to ensure this isn't the case. Paste the certificate data into the appropriate configuration field post-install

## Infrastructure Paving
Edit the Makefile to set some default values and reduce command-line toil. When building out the infrastructure, you're going to need to set a few values or specify them from the command-line. It's suggested that you do not save passwords in the Makefile and instead override them in the terminal to avoid committing secrets by accident.

You should be setting these values in the `Makefile` to suit your environment
* EL8000_CONTEXT
* BASE_URL
* RKE2_VIP

Below is the ordering for a from-scratch provisioning process.

### Certs
Certs can be generated and/or imported if they were generated elsewhere. This utilizes cert-manager and LetsEncrypt ClusterIssuer so it requires internet access or a cloudflare token and ownership of the domain.

If you have a cloudflare token for the API that manages your desired `BASE_URL`, you can use `make certs` to generate the certificates using cert-manager. You can also export them using `make certs-export`. If you do not have this ability but do have saved secrets with TLS certs, you can use `make certs-import` to import them. See the directive for the pathing.

See this process play out below, we generate the certs live vs importing and then deploy the registry and code-store
```console

> make certs EL8000_CONTEXT=my-harvester CLOUDFLARE_TOKEN='mycloudflaretoken'

===>Making Certificates
Switched to context "my-harvester".
NAME: cert-manager
LAST DEPLOYED: Fri Oct 14 15:17:51 2022
NAMESPACE: cert-manager
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
cert-manager v1.7.3 has been deployed successfully!

In order to begin issuing certificates, you will need to set up a ClusterIssuer
or Issuer resource (for example, by creating a 'letsencrypt-staging' issuer).

More information on the different types of issuers and how to configure them
can be found in our documentation:

https://cert-manager.io/docs/configuration/

For information on how to configure cert-manager to automatically provision
Certificates for Ingress resources, take a look at the `ingress-shim`
documentation:

https://cert-manager.io/docs/usage/ingress/
secret/cloudflare-api-token-secret created
clusterissuer.cert-manager.io/letsencrypt-prod created
namespace/harbor created
certificate.cert-manager.io/harbor-prod created
namespace/git created
certificate.cert-manager.io/gitea-prod created
Error from server (AlreadyExists): namespaces "cattle-system" already exists
certificate.cert-manager.io/rancher-airgap created

> kc get cert -A
NAMESPACE       NAME                READY   SECRET                          AGE
cattle-system   rancher-airgap      False   tls-rancher-ingress             7s
git             gitea-prod          False   gitea-prod-certificate          9s
harbor          harbor-prod         False   harbor-prod-certificate         11s

> kc get cert -A
NAMESPACE       NAME             READY   SECRET                    AGE
cattle-system   rancher-airgap   True    tls-rancher-ingress       95s
git             gitea-prod       True    gitea-prod-certificate    97s
harbor          harbor-prod      True    harbor-prod-certificate   99s

```

### Harbor
As everything in the Rancher stack sans Harvester, Gitea, and Harbor itself will need a registy and helm chart repo, there's a good amount of images that need to be uploaded into the infrastructure instance of Harbor (harbor.mustafar.lol). 
There are multiple Makefile targets built around pulling all of these images and pushing the images into Harbor. Ideally, when setting up a PoC instance, the images can be preloaded onto permanent storage and uploaded to Harbor to avoid having to download the images on public internet (about 33gb total).

Installing Harbor is very easy. You can set the admin password in the `bootstrap/harbor/values.yaml` file. Ensure your harvester kubeconfig is in your context and the Makefile values are set and just run `make registry`

```console
> make registry EL8000_CONTEXT=my-harvester

===> Installing Registry
Switched to context "my-harvester".
NAME: harbor
LAST DEPLOYED: Fri Oct 14 15:20:56 2022
NAMESPACE: harbor
STATUS: deployed
REVISION: 1
TEST SUITE: None
NOTES:
Please wait for several minutes for Harbor deployment to complete.
Then you should be able to visit the Harbor portal at https://harbor.mustafar.lol
For more details, please visit https://github.com/goharbor/harbor

> kc get po -n harbor
NAME                                    READY   STATUS    RESTARTS      AGE
harbor-chartmuseum-59fb8f66bc-rq4l2     1/1     Running   0             108s
harbor-core-75784f5455-8qd9k            1/1     Running   1 (41s ago)   108s
harbor-database-0                       1/1     Running   0             108s
harbor-jobservice-6b469d74f4-6bz7q      1/1     Running   0             108s
harbor-notary-server-9b68fb76f-g2sj7    1/1     Running   1 (74s ago)   108s
harbor-notary-signer-65d66d65f9-sbf2f   1/1     Running   1 (75s ago)   108s
harbor-portal-54c69ddd45-852zd          1/1     Running   0             108s
harbor-redis-0                          1/1     Running   0             108s
harbor-registry-7874d969d9-xm4hs        2/2     Running   0             108s
harbor-trivy-0                          1/1     Running   0             108s
```

#### Post-Install Tasks
After Harbor has been installed, there are some tasks that need to be manually performed to ensure it is properly configured. In order to finish bootstrapping Rancher onto Harvester, only the `rke2` and `rancher` based directives need to be used. However, for the full stack to function, there are many airgapped images that also need to be placed in the registry and the configurations consuming them expect them in a specific project format.

Projects in Harbor should all be public for convenience, they are listed here:
* goharbor
* grafana
* hashicorp
* jetstack
* kubewarden
* longhornio
* rancher

Under `bootstrap/rancher` there is a list of tarballs that should be uploaded (the rancher one can be skipped). The list of charts to uplaod mapped to their project are here:
* cert-manager => jetstack
* consul => hashicorp
* kubewarden => kubewarden
* loki-stack => grafana
* longhorn => longhornio
* neuvector => rancher
* rancher => rancher
* vault => hashicorp

The container images can be acquired from the `Makefile` targets:
* pull-rke2
* pull-rancher
* pull-misc

The images generated by those targets will be located in `/tmp` directory and can be uploaded using `make push-images HARBOR_PASSWORD='harbor-password' IMAGES_FILE='/tmp/imagefile.tar.gz`. These images should be copied to a hard-storage that can be reused so they don't need to be redownloaded. The image files are named below:
* rke2-images.tar.gz
* cert-manager-images.tar.gz
* rancher-images.tar.gz
* harbor-images.tar.gz 
* longhorn-images.tar.gz 
* loki-images.tar.gz 
* hashicorp-images.tar.gz 

### Gitea
Gitea is a lightweight and straight-forward code store that is easy to deploy using a Helm chart. It will be utilized in this demo as the `source of truth` for our GitOps processes. 

It is straight-forward to install using `make git GIT_ADMIN_PASSWORD='your_admin_password'`. The password you define here will be needed for initial login and configuration.

```console

> make git EL8000_CONTEXT=my-harvester GIT_ADMIN_PASSWORD='Password123'
Switched to context "my-harvester".
NAME: gitea
LAST DEPLOYED: Fri Oct 14 15:21:52 2022
NAMESPACE: git
STATUS: deployed
REVISION: 1
NOTES:
1. Get the application URL by running these commands:
  https://git.mustafar.lol/

> kc get po -n git
NAME                               READY   STATUS    RESTARTS   AGE
gitea-0                            1/1     Running   0          13m
gitea-memcached-6ff546bdf6-qghq2   1/1     Running   0          13m
gitea-postgresql-0                 1/1     Running   0          13m

```

#### Post-Install Tasks
TODO
* Create Project
* Add SSH key
* Push fleet-stack repo

### Infra target
The infra target will use Terraform to pave your Harvester instance with several base configuration items. The two major components are the VLAN-based networks as well as an Ubuntu-20.04 cloud image. Both components are used by downstream processes.

Using `make infra` will pave your Harvester instance pretty quickly. Be aware that the Ubuntu image is downloaded from Canonical's cloud image repository for an official signed image.

```console
> make infra EL8000_CONTEXT=my-harvester

=====> Terraforming Infra
/Library/Developer/CommandLineTools/usr/bin/make terraform COMPONENT=infra
Switched to context "my-harvester".

<snip>

Plan: 5 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + dev_network_name      = (known after apply)
  + prod_network_name     = (known after apply)
  + sandbox_network_name  = (known after apply)
  + services_network_name = (known after apply)
  + ubuntu_image_name     = (known after apply)

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

harvester_network.sandbox: Creating...
harvester_image.ubuntu-2004: Creating...
harvester_network.dev: Creating...
harvester_network.services: Creating...
harvester_network.prod: Creating...
harvester_network.dev: Creation complete after 1s [id=default/dev]
harvester_network.sandbox: Creation complete after 1s [id=default/sandbox]
harvester_network.prod: Creation complete after 1s [id=default/prod]
harvester_network.services: Creation complete after 1s [id=default/services]
harvester_image.ubuntu-2004: Still creating... [10s elapsed]
harvester_image.ubuntu-2004: Still creating... [20s elapsed]
harvester_image.ubuntu-2004: Still creating... [30s elapsed]
harvester_image.ubuntu-2004: Creation complete after 31s [id=default/ubuntu-2004]

Apply complete! Resources: 5 added, 0 changed, 0 destroyed.

Outputs:

dev_network_name = "default/dev"
prod_network_name = "default/prod"
sandbox_network_name = "default/sandbox"
services_network_name = "default/services"
ubuntu_image_name = "default/ubuntu-2004"
```

### Jumpbox
Provided as a multi-use case component, there is a jumpbox target in the Makefile that will pre-build an Ubuntu jumpbox that contains a few key components in the case that your local operating environment is having trouble.

Using `make jumpbox` will build your jumpbox and place it on the Services network. The provisioned IP address will be reported to the terminal window. The SSH key is generated as part of the process and is available by using `make jumpbox-key`, the user is `ubuntu`.

```console
> make jumpbox EL8000_CONTEXT=my-harvester

====> Terraforming Jumpbox
/Library/Developer/CommandLineTools/usr/bin/make terraform COMPONENT=jumpbox
Switched to context "my-harvester".

<snip>

Plan: 4 to add, 0 to change, 0 to destroy.

Changes to Outputs:
  + jumpbox_key_file = "./jumpbox"
  + jumpbox_ssh_key  = (sensitive value)
  + jumpbox_vm_ip    = (known after apply)

Do you want to perform these actions?
  Terraform will perform the actions described above.
  Only 'yes' will be accepted to approve.

  Enter a value: yes

tls_private_key.rsa_key: Creating...
tls_private_key.rsa_key: Creation complete after 2s [id=b236caa5b75206dc35eef6f0d4f7c0d2d06ea211]
harvester_ssh_key.jumpbox-key: Creating...
local_sensitive_file.jumpbox_key_pem: Creating...
local_sensitive_file.jumpbox_key_pem: Creation complete after 0s [id=f11cc9405d00d9f71bbb6d654d2b6622a6e88b79]
harvester_virtualmachine.jumpbox: Creating...
harvester_ssh_key.jumpbox-key: Creation complete after 0s [id=default/jumpbox-key]
harvester_virtualmachine.jumpbox: Still creating... [10s elapsed]
harvester_virtualmachine.jumpbox: Still creating... [20s elapsed]
harvester_virtualmachine.jumpbox: Still creating... [30s elapsed]
harvester_virtualmachine.jumpbox: Still creating... [40s elapsed]
harvester_virtualmachine.jumpbox: Still creating... [50s elapsed]
harvester_virtualmachine.jumpbox: Still creating... [1m0s elapsed]
harvester_virtualmachine.jumpbox: Creation complete after 1m0s [id=default/ubuntu-jumpbox]

Apply complete! Resources: 4 added, 0 changed, 0 destroyed.

Outputs:

jumpbox_key_file = "./jumpbox"
jumpbox_ssh_key = <sensitive>
jumpbox_vm_ip = "10.11.5.74"

> make jumpbox-key EL8000_CONTEXT=my-harvester

====> Grabbing generated SSH key
/Library/Developer/CommandLineTools/usr/bin/make terraform-value COMPONENT=jumpbox FIELD=".jumpbox_ssh_key.value"
Switched to context "my-harvester".
-----BEGIN RSA PRIVATE KEY-----
...
-----END RSA PRIVATE KEY-----

```

## Rancher Manager Installation
Rancher Manager is installed via Terraform and uses a set of modules that will build out an airgapped RKE2 cluster. Many configurations are defaulted, but the control-plane and worker node counts are defaulted in the Makefile allowing you to control them based on desired state. If you wish to alter the per-node VM compute/memory allocations, please see the `terraform/rancher/variables.tf` file and make adjustments to defaults where necessary. This is not a typical production setup so there is no tfvars file to keep things clean and portable.

Configurable flags for Rancher's make-based deployment:
* RANCHER_HA_MODE = (true or false) -- defaults to false
* RANCHER_WORKER_COUNT = Number above 1, suggested 2 or 3, defaults to 3
* RANCHER_NODE_SIZE = Number in Gigabytes, 20 is default and in the format of `20Gi`

Deploy Rancher using `make rancher` with any args defined after, or none if you want default values.