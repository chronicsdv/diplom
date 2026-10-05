output "control_plane_ips" {
  description = "Публичные IP control plane"
  value       = { for i in yandex_compute_instance.control_plane : i.name => i.network_interface[0].nat_ip_address }
}

output "worker_ips" {
  description = "Публичные IP воркеров"
  value       = { for i in yandex_compute_instance.worker : i.name => i.network_interface[0].nat_ip_address }
}

output "kube_api_endpoint" {
  description = "Адрес API Kubernetes (для kubeconfig и GitHub Secrets)"
  value       = "https://${yandex_compute_instance.control_plane[0].network_interface[0].nat_ip_address}:6443"
}

output "ssh_first_cp" {
  description = "Команда для входа на первую control plane"
  value       = "ssh -i ${trimsuffix(var.ssh_public_key_path, ".pub")} ${var.ssh_user}@${yandex_compute_instance.control_plane[0].network_interface[0].nat_ip_address}"
}
