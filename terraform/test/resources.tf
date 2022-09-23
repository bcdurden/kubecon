terraform {
  required_version = ">= 0.13"
  required_providers {
    harvester = {
      source  = "harvester/harvester"
      version = "0.5.1"
    }
  }
  backend "kubernetes" {
    secret_suffix    = "state-test"
    config_path      = "~/.kube/config"
  }
}

provider "harvester" {
}
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

  # ssh_keys = [
  #   data.harvester_ssh_key.socpac.id
  # ]

  network_interface {
    name           = "default"
    network_name   = "default/vlan190"
    wait_for_lease = true
  }

  disk {
    name       = "rootdisk"
    type       = "disk"
    size       = "10Gi"
    bus        = "virtio"
    boot_order = 1

    image       = "default/ubuntu-2004"
    auto_delete = true
  }

  cloudinit {
    type      = "noCloud"
    
    user_data    = <<EOT
      #cloud-config
      user: ubuntu
      password: root
      package_update: true
      packages:
      - qemu-guest-agent
      runcmd:
      - - systemctl
        - enable
        - '--now'
        - qemu-guest-agent.service
    EOT
    network_data = ""
  }
}