locals {
  ipv4_re = "^[0-9]+\\.[0-9]+\\.[0-9]+\\.[0-9]+$"

  # Hyper-V отдаёт и IPv4, и IPv6: берём только IPv4
  control_planes = [for i in hyperv_machine_instance.control_plane : {
    name       = i.name
    public_ip  = [for ip in i.network_adaptors[0].ip_addresses : ip if can(regex(local.ipv4_re, ip))][0]
    private_ip = [for ip in i.network_adaptors[0].ip_addresses : ip if can(regex(local.ipv4_re, ip))][0]
  }]
  workers = [for i in hyperv_machine_instance.worker : {
    name       = i.name
    public_ip  = [for ip in i.network_adaptors[0].ip_addresses : ip if can(regex(local.ipv4_re, ip))][0]
    private_ip = [for ip in i.network_adaptors[0].ip_addresses : ip if can(regex(local.ipv4_re, ip))][0]
  }]
}

# Inventory для Ansible/Kubespray (тот же формат, что и в Яндекс-варианте)
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.ini"
  content = templatefile("${path.module}/inventory.tftpl", {
    control_planes  = local.control_planes
    workers         = local.workers
    ssh_user        = var.ssh_user
    ssh_private_key = var.ssh_private_key_path
  })
}

# IP control plane в сертификат API-сервера
resource "local_file" "kubespray_api_cert" {
  filename = "${path.module}/../ansible/inventory/group_vars/k8s_cluster/api-cert.yml"
  content = yamlencode({
    supplementary_addresses_in_ssl_keys = [for n in local.control_planes : n.public_ip]
  })
}
