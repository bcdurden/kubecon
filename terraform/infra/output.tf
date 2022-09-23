output "ubuntu_image_name" {
    value = harvester_image.ubuntu-2004.id
}
output "services_network_name" {
    value = harvester_network.services.id
}
output "workloads1_network_name" {
    value = harvester_network.workloads1.id
}
output "workloads2_network_name" {
    value = harvester_network.workloads2.id
}
output "workloads3_network_name" {
    value = harvester_network.workloads3.id
}