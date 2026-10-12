output "control_plane_ips" {
  value = { for n in local.control_planes : n.name => n.public_ip }
}

output "worker_ips" {
  value = { for n in local.workers : n.name => n.public_ip }
}

# Имя вывода такое же, как в Яндекс-варианте: up.sh работает с обоими
output "kube_api_endpoint" {
  value = "https://${local.control_planes[0].public_ip}:6443"
}

output "ssh_first_cp" {
  value = "ssh -i ${var.ssh_private_key_path} ${var.ssh_user}@${local.control_planes[0].public_ip}"
}
