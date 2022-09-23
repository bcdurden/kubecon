resource "harvester_virtualmachine" "jumpbox" {
  name                 = "ubuntu-jumpbox"
  namespace            = "default"
  restart_after_update = true

  description = "Jumpbox VM"
  tags = {
    ssh-user = "ubuntu"
  }

  cpu    = 2
  memory = "4Gi"

  run_strategy = "RerunOnFailure"
  hostname     = "jumpbox"
  machine_type = "q35"

  network_interface {
    name           = "default"
    network_name   = data.harvester_network.services.id
    wait_for_lease = true
  }

  disk {
    name       = "rootdisk"
    type       = "disk"
    size       = "40Gi"
    bus        = "virtio"
    boot_order = 1

    image       = data.harvester_image.ubuntu2004.id
    auto_delete = true
  }

  cloudinit {
    type      = "noCloud"
    
    user_data    = <<EOT
      #cloud-config
      package_update: true
      packages:
      - qemu-guest-agent
      runcmd:
      - - systemctl
        - enable
        - '--now'
        - qemu-guest-agent.service
      ssh_authorized_keys: 
      - ${tls_private_key.rsa_key.public_key_openssh}
    EOT
    network_data = ""
  }
}