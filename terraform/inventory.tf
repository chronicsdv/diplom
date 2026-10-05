# Генерируем inventory для Ansible/Kubespray из созданных ВМ
resource "local_file" "ansible_inventory" {
  filename = "${path.module}/../ansible/inventory/hosts.ini"
  content = templatefile("${path.module}/inventory.tftpl", {
    control_planes = [for i in yandex_compute_instance.control_plane : {
      name       = i.name
      public_ip  = i.network_interface[0].nat_ip_address
      private_ip = i.network_interface[0].ip_address
    }]
    workers = [for i in yandex_compute_instance.worker : {
      name       = i.name
      public_ip  = i.network_interface[0].nat_ip_address
      private_ip = i.network_interface[0].ip_address
    }]
    ssh_user        = var.ssh_user
    ssh_private_key = trimsuffix(var.ssh_public_key_path, ".pub")
  })
}

# Публичные IP control plane нужно добавить в сертификат API-сервера,
# иначе kubectl снаружи ругнётся на TLS. Kubespray читает эту переменную.
resource "local_file" "kubespray_api_cert" {
  filename = "${path.module}/../ansible/inventory/group_vars/k8s_cluster/api-cert.yml"
  content = yamlencode({
    supplementary_addresses_in_ssl_keys = [
      for i in yandex_compute_instance.control_plane : i.network_interface[0].nat_ip_address
    ]
  })
}
