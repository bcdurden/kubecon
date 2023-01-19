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
TBD

## Prep Harvester's Ubuntu OS Image
To make this special image, we'll need to pull down the previously mentioned OS image to our local workstation and then do some work upon it using `guestfs` tools. This is slightly involved, but once finished, you'll have 80% of the manual steps above canned into a single image making it very easy to automate in an airgap. If you are not using Harvester, this image is in qcow2 format and should be usable in different HCI solutions, however your Terraform code will look different. Try to follow along, regardless, so the process around how you would bootstrap the cluster (and Rancher) from Terraform is understood at a high-level.

```bash
wget http://cloud-images.ubuntu.com/releases/focal/release/ubuntu-20.04-server-cloudimg-amd64.img
sudo apt install -y libguestfs-tools
```

Before we get started, we'll need to expand the filesystem of the cloud image because some of the files we are downloading are a little large. I'm using 3 gigs here, but if you're going to install something large like nvidia-drivers, use as much space as you like. We'll condense the image back down later.
```bash
sudo virt-filesystems --long -h --all -a ubuntu-20.04-server-cloudimg-amd64.img
truncate -r ubuntu-20.04-server-cloudimg-amd64.img ubuntu-rke2.img
truncate -s +3G ubuntu-rke2.img
sudo virt-resize --expand /dev/sda1 ubuntu-20.04-server-cloudimg-amd64.img ubuntu-rke2.img

```

Unfortunately `virt-resize` will also rename the partitions, which will screw up the bootloader. We now have to fix that by using virt-rescue and calling grub-install on the disk.

Start the `virt-rescue` app like this:
```bash
sudo virt-rescue ubuntu-rke2.img 
```

And then paste these commands in after the rescue app finishes starting:
```bash
mkdir /mnt
mount /dev/sda3 /mnt
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
chroot /mnt
grub-install /dev/sda
```

After that you can exit hitting `ctrl ]` and then hitting `q`.
```console
sudo virt-rescue ubuntu-rke2.img 
WARNING: Image format was not specified for '/home/ubuntu/ubuntu-rke2.img' and probing guessed raw.
         Automatically detecting the format is dangerous for raw images, write operations on block 0 will be restricted.
         Specify the 'raw' format explicitly to remove the restrictions.
Could not access KVM kernel module: No such file or directory
qemu-system-x86_64: failed to initialize KVM: No such file or directory
qemu-system-x86_64: Back to tcg accelerator
supermin: mounting /proc
supermin: ext2 mini initrd starting up: 5.1.20
...

The virt-rescue escape key is ‘^]’.  Type ‘^] h’ for help.

------------------------------------------------------------

Welcome to virt-rescue, the libguestfs rescue shell.

Note: The contents of / (root) are the rescue appliance.
You have to mount the guest’s partitions under /sysroot
before you can examine them.

groups: cannot find name for group ID 0
><rescue> mkdir /mnt
><rescue> mount /dev/sda3 /mnt
><rescue> mount --bind /dev /mnt/dev
><rescue> mount --bind /proc /mnt/proc
><rescue> mount --bind /sys /mnt/sys
><rescue> chroot /mnt
><rescue> grub-install /dev/sda
Installing for i386-pc platform.
Installation finished. No error reported.
```

Now we can inject both packages as well as run commands within the context of the image. We'll borrow some of the manual provisioning steps above and copy those pieces into the image. The run-command will do much of what our `pull_rke2` script was doing but focused around pulling binaries and install scripts. We will create the configurations for these items using cloud-init in later steps.

```bash
sudo virt-customize -a ubuntu-rke2.img --install qemu-guest-agent
sudo virt-customize -a ubuntu-rke2.img --run-command "mkdir -p /var/lib/rancher/rke2-artifacts && wget https://get.rke2.io -O /var/lib/rancher/install.sh && chmod +x /var/lib/rancher/install.sh"
sudo virt-customize -a ubuntu-rke2.img --run-command "wget https://kube-vip.io/k3s -O /var/lib/rancher/kube-vip-k3s && chmod +x /var/lib/rancher/kube-vip-k3s"
sudo virt-customize -a ubuntu-rke2.img --run-command "mkdir -p /var/lib/rancher/rke2/server/manifests && wget https://kube-vip.io/manifests/rbac.yaml -O /var/lib/rancher/rke2/server/manifests/kube-vip-rbac.yaml"
sudo virt-customize -a ubuntu-rke2.img --run-command "cd /var/lib/rancher/rke2-artifacts && curl -sLO https://github.com/rancher/rke2/releases/download/v1.24.8+rke2r1/rke2.linux-amd64.tar.gz"
sudo virt-customize -a ubuntu-rke2.img --run-command "cd /var/lib/rancher/rke2-artifacts && curl -sLO https://github.com/rancher/rke2/releases/download/v1.24.8+rke2r1/sha256sum-amd64.txt"
sudo virt-customize -a ubuntu-rke2.img --run-command "cd /var/lib/rancher/rke2-artifacts && curl -sLO https://github.com/rancher/rke2/releases/download/v1.24.8+rke2r1/rke2-images.linux-amd64.tar.zst"
sudo virt-customize -a ubuntu-rke2.img --run-command "echo -n > /etc/machine-id"
```

If we look at the image we just created, we can see it is quite large!
```console
ubuntu@jumpbox:~$ ll ubuntu*
-rw-rw-r-- 1 ubuntu ubuntu  637927424 Dec 13 22:16 ubuntu-20.04-server-cloudimg-amd64.img
-rw-rw-r-- 1 ubuntu ubuntu 3221225472 Dec 19 14:40 ubuntu-rke2.img
```

We need to shrink it back using virt-sparsify. This looks for any unused space (most of what we expanded) and then removes that from the physical image. Along the way we'll want to convert and then compress this image:
```bash
sudo virt-sparsify --convert qcow2 --compress ubuntu-rke2.img ubuntu-rke2-airgap-harvester.img
```

Example of our current image and cutting the size in half:
```console
ubuntu@jumpbox:~$ sudo virt-sparsify --convert qcow2 --compress ubuntu-rke2.img ubuntu-rke2-airgap-harvester.img
[   0.0] Create overlay file in /tmp to protect source disk
[   0.0] Examine source disk
 100% ⟦▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒⟧ --:--
[  14.4] Fill free space in /dev/sda2 with zero
 100% ⟦▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒⟧ --:--
[  17.5] Fill free space in /dev/sda3 with zero
 100% ⟦▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒▒⟧ 00:00
[  21.8] Copy to destination and make sparse
[ 118.8] Sparsify operation completed with no errors.
virt-sparsify: Before deleting the old disk, carefully check that the 
target disk boots and works correctly.
ubuntu@jumpbox:~$ ll ubuntu*
-rw-rw-r-- 1 ubuntu ubuntu  637927424 Dec 13 22:16 ubuntu-20.04-server-cloudimg-amd64.img
-rw-r--r-- 1 root   root   1562816512 Dec 19 15:00 ubuntu-rke2-airgap-harvester.img
-rw-rw-r-- 1 ubuntu ubuntu 3221225472 Dec 19 14:40 ubuntu-rke2.img
```

What we have now is a customized image named `ubuntu-rke2-airgap-harvester.img` containing the RKE2 binaries and install scripts that we can later invoke in cloud-init. Let's upload this to Harvester now. The easiest way to upload into Harvester is host the image somewhere so Harvester can pull it. If you want to manually upload it from your web session, you stand the risk of it being interrupted by your web browser and having to start over.

Since my VM is hosted in my same harvester instance, I'm going to use a simple `python3` fileserver in my workspace directory:
```bash
python3 -m http.server 9900
```

See it running here:
```console
ubuntu@jumpbox:~$ python3 -m http.server 9900
Serving HTTP on 0.0.0.0 port 9900 (http://0.0.0.0:9900/) ...
```

From my web browser I can visit this URL at http://<my_jumpbox_ip>:9900 and 'copy link' on the `ubuntu-rke2-airgap-harvester.img` file.

![filehost](images/filehost.png)

And then create a new Harvester image and paste the URL into the field. The file should download quickly here as the VM is co-located on the Harvester box so it is effectively a local network copy.

![filehost](images/createimage.png)
![images](images/images.png)

Now using the earlier steps in the manual provivisoning, we can create a test VM to ensure the image is good to go. We can alter our cloud-init now as we don't need any new packages or package updates, the qemu agent just needs to be enabled so the IP reports correctly. My key hash is injected automatically but I removed the package update and install commands.
```yaml
#cloud-config
runcmd:
  - - systemctl
    - enable
    - --now
    - qemu-guest-agent.service
ssh_authorized_keys:
  - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDZk5zkAj2wbSs1r/AesCC7t6CtF6yxmCjlXgzqODZOujVscV6PZzIti78dIhv3Yqtii/baFH0PfqoHZk9eayjZMcp+K+6bi4lSwszzDhV3aGLosPRNOBV4uT+RToEmiXwPtu5rJSRAyePu0hdbuOdkaf0rGjyUoMbqJyGuVIO3yx/+zAuS8hFGeV/rM2QEhzPA4QiR40OAW9ZDyyTVDU0UEhwUNQESh+ZM2X9fe5VIxNZcydw1KGwzj8t+6WuYBFvPKYR5sylAnocBWzAGKh+zHgZU5O5TwC1E92uPgUWNwMoFdyZRaid0sKx3O3EqeIJZSqlfoFhz3Izco+QIx4iqXU9jIVFtnTb9nCN/boXx7uhCfdaJ0WdWQEQx+FX092qE6lfZFiaUhZI+zXvTeENqVfcGJSXDhDqDx0rbbpvXapa40XZS/gk0KTny2kYXBATsUwZqmPpZF9njJ+1Hj/KSNhFQx1LcIQVvXP+Ie8z8MQleaTTD0V9+Zkw2RBkVPYc5Vb8m8XCy1xf4DoP6Bmb4g3iXS17hYQEKj1bfBMbDfZdexbSPVOUPXUMR2aMxz8R3OaswPimLmo0uPiyYtyVQCuJu62yrao33knVciV/xlifFsqrNDgribDNr4RKnrIX2eyszCiSv2DoZ6VeAhg8i6v6yYL7RhQM31CxYjnZK4Q==
```

I'll not show the other images here, but show the SSH output of the started VM:
```console
> ssh -i ~/.ssh/harvester_test ubuntu@10.10.5.77
The authenticity of host '10.10.5.77 (10.10.5.77)' can't be established.
ED25519 key fingerprint is SHA256:5EhVyhModCMWMtI0zcd+dErCDnjVGlkmI/8CDuHOJ2g.
This key is not known by any other names
...
Ubuntu comes with ABSOLUTELY NO WARRANTY, to the extent permitted by
applicable law.

To run a command as administrator (user "root"), use "sudo <command>".
See "man sudo_root" for details.

ubuntu@test-image:~$ ll /var/lib/rancher
total 44
drwxr-xr-x  4 root root  4096 Dec 19 14:37 ./
drwxr-xr-x 41 root root  4096 Dec 19 15:18 ../
-rwxr-xr-x  1 root root 22291 Dec 19 14:36 install.sh*
-rwxr-xr-x  1 root root  1397 Dec 19 14:36 kube-vip-k3s*
drwxr-xr-x  3 root root  4096 Dec 19 14:37 rke2/
drwxr-xr-x  2 root root  4096 Dec 19 14:38 rke2-artifacts/
ubuntu@test-image:~$ ll /var/lib/rancher/rke2-artifacts/
total 840560
drwxr-xr-x 2 root root      4096 Dec 19 14:38 ./
drwxr-xr-x 4 root root      4096 Dec 19 14:37 ../
-rw-r--r-- 1 root root 812363060 Dec 19 14:40 rke2-images.linux-amd64.tar.zst
-rw-r--r-- 1 root root  48350150 Dec 19 14:37 rke2.linux-amd64.tar.gz
-rw-r--r-- 1 root root      3626 Dec 19 14:38 sha256sum-amd64.txt
ubuntu@test-image:~$ ll /var/lib/rancher/rke2/server/manifests/
total 12
drwxr-xr-x 2 root root 4096 Dec 19 14:37 ./
drwxr-xr-x 3 root root 4096 Dec 19 14:37 ../
-rw-r--r-- 1 root root  805 Dec 19 14:37 kube-vip-rbac.yaml
```

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
Rancher Manager is installed via Terraform and uses a set of modules that will build out an airgapped RKE2 cluster. Many configurations are defaulted, but the control-plane and worker node counts are defaulted in the Makefile allowing you to control them based on desired state. If you wish to alter the per-node VM compute/memory allocations, please see the `terraform/rancher/variables.tf` file and make adjustments to defaults where necessary. This is not a typical production setup so there is no tfvars file, this keep things clean and portable.

Configurable flags for Rancher's make-based deployment:
* RANCHER_HA_MODE = (true or false) -- defaults to false
* RANCHER_WORKER_COUNT = Number greater than 0, suggested 2 or 3, defaults to 3
* RANCHER_NODE_SIZE = Number in Gigabytes, 20 is default and in the format of `20Gi`
* RKE2_VIP = kubevip assignment for control plane node in RKE2 (defaults to 10.11.5.4)

Deploy Rancher using `make rancher` with any args defined after, or none if you want default values. This command will create an RKE2 cluster within the Harvester cluster and install Rancher upon it. After finishing it will pull the kubeconfig down into your local kubecontext and install a TLS certificate on it.

```console
> make rancher RANCHER_WORKER_COUNT=1 RKE2_VIP=10.11.5.4 EL8000_CONTEXT=my-harvester

====> Terraforming RKE2 + Rancher
Switched to context "my-harvester".
/Library/Developer/CommandLineTools/usr/bin/make terraform COMPONENT=rancher VARS='TF_VAR_harbor_url="harbor.mustafar.lol" TF_VAR_rancher_server_dns="rancher.mustafar.lol" TF_VAR_master_vip="10.11.5.4" TF_VAR_harbor_url="harbor.mustafar.lol" TF_VAR_worker_count=1 TF_VAR_control_plane_ha_mode=false TF_VAR_node_disk_size="20Gi"'
Switched to context "my-harvester".
Initializing modules...

...

tls_private_key.global_key: Creating...
tls_private_key.global_key: Creation complete after 0s [id=f2c24ab5b2ef91f5c52f902467786dfce6d95c11]
module.controlplane-nodes.harvester_virtualmachine.node-main: Creating...
module.controlplane-nodes.harvester_virtualmachine.node-main: Still creating... [50s elapsed]
module.controlplane-nodes.harvester_virtualmachine.node-main: Provisioning with 'remote-exec'...
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec): Connecting to remote host via SSH...
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec):   Host: 10.11.5.219
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec):   User: ubuntu
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec):   Password: false
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec):   Private key: true
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec):   Certificate: false
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec):   SSH Agent: true
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec):   Checking Host Key: false
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec):   Target Platform: unix
module.controlplane-nodes.harvester_virtualmachine.node-main: Still creating... [1m0s elapsed]
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec): Connected!
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec): Waiting for cloud-init to complete...
module.controlplane-nodes.harvester_virtualmachine.node-main: Still creating... [1m10s elapsed]
module.controlplane-nodes.harvester_virtualmachine.node-main: Still creating... [1m20s elapsed]
module.controlplane-nodes.harvester_virtualmachine.node-main: Still creating... [1m30s elapsed]
module.controlplane-nodes.harvester_virtualmachine.node-main (remote-exec): Completed cloud-init!
module.controlplane-nodes.harvester_virtualmachine.node-main: Creation complete after 1m35s [id=default/rke2-mgmt-controlplane-0]
ssh_resource.retrieve_config: Creating...
module.worker.harvester_virtualmachine.node[0]: Creating...
ssh_resource.retrieve_config: Creation complete after 1s [id=5577006791947779410]
local_file.kube_config_server_yaml: Creating...
local_file.kube_config_server_yaml: Creation complete after 0s [id=1dc12cd2784bcf2c483b0f2eae3c15cb0ce4c8b5]
module.worker.harvester_virtualmachine.node[0]: Still creating... [1m0s elapsed]
module.worker.harvester_virtualmachine.node[0]: Provisioning with 'remote-exec'...
module.worker.harvester_virtualmachine.node[0] (remote-exec): Connecting to remote host via SSH...
module.worker.harvester_virtualmachine.node[0] (remote-exec):   Host: 10.11.5.64
module.worker.harvester_virtualmachine.node[0] (remote-exec):   User: ubuntu
module.worker.harvester_virtualmachine.node[0] (remote-exec):   Password: false
module.worker.harvester_virtualmachine.node[0] (remote-exec):   Private key: true
module.worker.harvester_virtualmachine.node[0] (remote-exec):   Certificate: false
module.worker.harvester_virtualmachine.node[0] (remote-exec):   SSH Agent: true
module.worker.harvester_virtualmachine.node[0] (remote-exec):   Checking Host Key: false
module.worker.harvester_virtualmachine.node[0] (remote-exec):   Target Platform: unix
module.worker.harvester_virtualmachine.node[0]: Still creating... [1m10s elapsed]
module.worker.harvester_virtualmachine.node[0] (remote-exec): Connected!
module.worker.harvester_virtualmachine.node[0] (remote-exec): Waiting for cloud-init to complete...
module.worker.harvester_virtualmachine.node[0] (remote-exec): Completed cloud-init!
module.worker.harvester_virtualmachine.node[0]: Creation complete after 1m16s [id=default/rke2-mgmt-worker-0]
helm_release.cert_manager: Creating...
helm_release.cert_manager: Still creating... [20s elapsed]
helm_release.cert_manager: Creation complete after 24s [id=cert-manager]
helm_release.rancher_server: Creating...
helm_release.rancher_server: Still creating... [1m10s elapsed]
helm_release.rancher_server: Creation complete after 1m13s [id=rancher]

Apply complete! Resources: 7 added, 0 changed, 0 destroyed.

Outputs:

kube = <sensitive>
ssh_key = <sensitive>
ssh_pubkey = <<EOT
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC7QpnkfcaXro+dEHWwjK7zk5y0WoRcnsqvAS4csVV79AT38nQ+W6Uuix5z+LOpYsPad/xzZSX+n2qipLJZiNBxIEksXyjU3m5go1V4+Kb+hzL0t79yNy8SMdWaIMJgHp/tDQfJDXPtQ/FKkOJCGnnDvP/W18Wes3zPunXkMsXddDRTYnzJ8iuFq8UZ2z5gg3OSYOZ7iO8fXOMd1XJW/ynNvDZN3EGbRTZEWahcYnREGbl+/wnxXh93TYXSRZ5+lPSOAI4T/fwpoq3x0P58y7rAVRLoAQNBBleP+NhhWyBY8rdcdjh6v57Wk9xr+PUzt+7DFaHC5yewKRR0ZsKfQmTV

EOT
Add Context: rancher-el8000 
「/tmp/rancher-el8000.yaml」 write successful!
+------------+-------------------+-----------------------+--------------------+-----------------------------------+--------------+
|   CURRENT  |        NAME       |        CLUSTER        |        USER        |               SERVER              |   Namespace  |
+============+===================+=======================+====================+===================================+==============+
|      *     |    my-harvester   |   cluster-8c5g87ht4k  |   user-8c5g87ht4k  |   https://10.11.0.20/k8s/cluster  |    default   |
|            |                   |                       |                    |              s/local              |              |
+------------+-------------------+-----------------------+--------------------+-----------------------------------+--------------+
|            |   rancher-el8000  |   cluster-bfgk6bft59  |   user-bfgk6bft59  |       https://10.11.5.4:6443      |    default   |
+------------+-------------------+-----------------------+--------------------+-----------------------------------+--------------+

Switched to context "rancher-el8000".
secret/tls-rancher-ingress created
Switched to context "my-harvester".
```