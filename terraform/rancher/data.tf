data "harvester_network" "services" {
  name      = "services"
  namespace = "default"
}
data "harvester_network" "workloads1" {
  name      = "workloads1"
  namespace = "default"
}
data "harvester_network" "workloads2" {
  name      = "workloads2"
  namespace = "default"
}
data "harvester_network" "workloads3" {
  name      = "workloads3"
  namespace = "default"
}
data "harvester_image" "ubuntu2004" {
  name      = "ubuntu-2004"
  namespace = "default"
}