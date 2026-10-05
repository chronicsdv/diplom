# Свежий образ Ubuntu 24.04 LTS из публичного каталога Яндекса
data "yandex_compute_image" "ubuntu" {
  family = "ubuntu-2404-lts"
}

locals {
  metadata = {
    ssh-keys = "${var.ssh_user}:${trimspace(file(pathexpand(var.ssh_public_key_path)))}"
  }
}

resource "yandex_compute_instance" "control_plane" {
  count                     = var.control_plane_count
  name                      = "${var.name_prefix}-cp-${count.index + 1}"
  hostname                  = "${var.name_prefix}-cp-${count.index + 1}"
  platform_id               = "standard-v3"
  zone                      = var.zone
  allow_stopping_for_update = true

  resources {
    cores         = var.cp_cores
    memory        = var.cp_memory_gb
    core_fraction = var.cp_core_fraction
  }

  scheduling_policy {
    preemptible = var.cp_preemptible
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.cp_disk_gb
      type     = var.disk_type
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.k8s.id]
  }

  metadata = local.metadata
}

resource "yandex_compute_instance" "worker" {
  count                     = var.worker_count
  name                      = "${var.name_prefix}-worker-${count.index + 1}"
  hostname                  = "${var.name_prefix}-worker-${count.index + 1}"
  platform_id               = "standard-v3"
  zone                      = var.zone
  allow_stopping_for_update = true

  resources {
    cores         = var.worker_cores
    memory        = var.worker_memory_gb
    core_fraction = var.worker_core_fraction
  }

  scheduling_policy {
    preemptible = var.worker_preemptible
  }

  boot_disk {
    initialize_params {
      image_id = data.yandex_compute_image.ubuntu.id
      size     = var.worker_disk_gb
      type     = var.disk_type
    }
  }

  network_interface {
    subnet_id          = yandex_vpc_subnet.main.id
    nat                = true
    security_group_ids = [yandex_vpc_security_group.k8s.id]
  }

  metadata = local.metadata
}
