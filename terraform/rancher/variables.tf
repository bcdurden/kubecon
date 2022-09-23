variable "main_cluster_prefix" {
    type = string
    default = "rke2-mgmt-controlplane"
}
variable "worker_prefix" {
    type = string
    default = "rke2-mgmt-worker"
}
variable "kubeconfig_filename" {
    type = string
    default = "kube_config_server.yaml"
}
variable "cert_manager_version" {
  type        = string
  description = "Version of cert-manager to install alongside Rancher (format: 0.0.0)"
  default     = "1.7.1"
}

variable "rancher_version" {
  type        = string
  description = "Rancher server version (format v0.0.0)"
  default     = "2.6.7"
}
variable "master_vip" {
    type = string
    default = "10.10.16.4"
}
variable "rancher_server_dns" {
  type        = string
  description = "DNS host name of the Rancher server"
  default = "rancher.airgap.platformfeverdream.io"
}
