resource "yandex_vpc_network" "main" {
  name = "${var.name_prefix}-net"
}

resource "yandex_vpc_subnet" "main" {
  name           = "${var.name_prefix}-subnet"
  zone           = var.zone
  network_id     = yandex_vpc_network.main.id
  v4_cidr_blocks = ["10.10.0.0/24"]
}

resource "yandex_vpc_security_group" "k8s" {
  name       = "${var.name_prefix}-k8s-sg"
  network_id = yandex_vpc_network.main.id

  ingress {
    description    = "SSH только с разрешённых адресов"
    protocol       = "TCP"
    port           = 22
    v4_cidr_blocks = var.allowed_ssh_cidrs
  }

  ingress {
    description    = "Kubernetes API"
    protocol       = "TCP"
    port           = 6443
    v4_cidr_blocks = var.kube_api_cidrs
  }

  ingress {
    description    = "HTTP (ingress)"
    protocol       = "TCP"
    port           = 80
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description    = "HTTPS (ingress)"
    protocol       = "TCP"
    port           = 443
    v4_cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description       = "Весь трафик между нодами кластера"
    protocol          = "ANY"
    predefined_target = "self_security_group"
  }

  egress {
    description    = "Исходящий трафик куда угодно"
    protocol       = "ANY"
    v4_cidr_blocks = ["0.0.0.0/0"]
  }
}
