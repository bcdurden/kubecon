module "controlplane-nodes" {
  source = "./modules/controlplane-node"

  node_name_prefix = var.main_cluster_prefix
  node_image_id = data.harvester_image.ubuntu2004.id
  vlan_id = data.harvester_network.services.id
  master_vip = var.master_vip
  ssh_key = tls_private_key.global_key.private_key_pem
  ssh_pubkey = tls_private_key.global_key.public_key_openssh

  # ha_mode = true
}

module "worker" {
  source = "./modules/worker-node"
  depends_on = [
    module.controlplane-nodes.controlplane_node
  ]

  worker_count = 3
  node_prefix = var.worker_prefix
  node_image_id = data.harvester_image.ubuntu2004.id
  vlan_id = data.harvester_network.services.id
  master_vip = var.master_vip
  ssh_key = tls_private_key.global_key.private_key_pem
  ssh_pubkey = tls_private_key.global_key.public_key_openssh
}