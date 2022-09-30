variable "node_name_prefix" {
    type = string
}
variable "namespace" {
    type = string
    default = "default"
}
variable "disk_size" {
    type = string
    default = "40Gi"
}
variable "node_image_id" {
    type = string
}
variable "ssh_keys" {
    type = list
    default = []
}
variable "vlan_id" {
    type = string
}
# variable "user_data" {
#     type = string
#     default = <<EOT
#         #cloud-config
#         package_update: true
#         packages:
#         - qemu-guest-agent
#         runcmd:
#         - - systemctl
#             - enable
#             - '--now'
#             - qemu-guest-agent.service
#       EOT
# }
variable "master_hostname" {
    type = string
    default = "rke2master"
}
variable "master_vip" {
    type = string
}
variable "master_vip_interface" {
    type = string
    default = "enp1s0"
}
variable "network_data" {
    type = string
    default = ""
}
variable "rke2_version" {
    type = string
    default = "v1.24.3+rke2r1"
}
variable "cluster_token" {
    type = string
    default = "my-shared-token"
}
variable "ssh_pubkey" {
    type = string
    default = ""
}
variable "ssh_key" {
    type = string
    default = ""
}
variable "ha_mode" {
    type = bool
    default = false
}
variable "controlplane_node_core_count" {
    type = string
    default = 2
}
variable "controlplane_node_memory_size" {
    type = string
    default = "4Gi"
}
variable "rke2_config_additions" {
    type = string
    default = <<EOT
system-default-registry: harbor.homelab.platformfeverdream.io
    
    EOT
}
variable "registry_endpoint" {
    type = string
    default = <<EOT

      - path: /etc/rancher/rke2/registries.yaml
        owner: root
        content: |
          mirrors:
            docker.io:
              endpoint:
                - "https://harbor.homelab.platformfeverdream.io"
            harbor.homelab.platformfeverdream.io:
              endpoint:
                - "https://harbor.homelab.platformfeverdream.io"
    EOT
}