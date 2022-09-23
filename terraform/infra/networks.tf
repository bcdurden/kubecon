resource "harvester_network" "services" {
  name      = "services"
  namespace = "default"

  vlan_id = 16
}
resource "harvester_network" "workloads1" {
  name      = "workloads1"
  namespace = "default"

  vlan_id = 32
}
resource "harvester_network" "workloads2" {
  name      = "workloads2"
  namespace = "default"

  vlan_id = 48
}
resource "harvester_network" "workloads3" {
  name      = "workloads3"
  namespace = "default"

  vlan_id = 64
}