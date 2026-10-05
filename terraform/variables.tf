variable "zone" {
  description = "Зона доступности Яндекс Облака"
  type        = string
  default     = "ru-central1-b"
}

variable "name_prefix" {
  description = "Префикс имён всех ресурсов"
  type        = string
  default     = "craftista"
}

# ---------- Доступ ----------
variable "ssh_public_key_path" {
  description = "Путь к публичному SSH-ключу (приватный лежит рядом без .pub)"
  type        = string
  default     = "~/.ssh/craftista.pub"
}

variable "ssh_user" {
  description = "Пользователь на ВМ (в образах Ubuntu — ubuntu)"
  type        = string
  default     = "ubuntu"
}

variable "allowed_ssh_cidrs" {
  description = "С каких адресов разрешён SSH, например [\"1.2.3.4/32\"]. Свой IP: curl ifconfig.me"
  type        = list(string)
}

variable "kube_api_cidrs" {
  description = "С каких адресов доступен API Kubernetes (6443). Для GitHub Actions нужен 0.0.0.0/0"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# ---------- Control plane ----------
variable "control_plane_count" {
  description = "Число control plane нод: 1 на разработке, 3 на защите (нечётное!)"
  type        = number
  default     = 1

  validation {
    condition     = contains([1, 3], var.control_plane_count)
    error_message = "control_plane_count должно быть 1 или 3."
  }
}

variable "cp_cores" {
  type    = number
  default = 2
}

variable "cp_memory_gb" {
  type    = number
  default = 4
}

variable "cp_core_fraction" {
  description = "Гарантированная доля vCPU, %: 20, 50 или 100 (меньше = дешевле, но медленнее)"
  type        = number
  default     = 100
}

variable "cp_disk_gb" {
  type    = number
  default = 30
}

# ---------- Workers ----------
variable "worker_count" {
  type    = number
  default = 3
}

variable "worker_cores" {
  type    = number
  default = 2
}

variable "worker_memory_gb" {
  type    = number
  default = 4
}

variable "worker_core_fraction" {
  type    = number
  default = 50
}

variable "worker_disk_gb" {
  type    = number
  default = 20
}

variable "disk_type" {
  description = "Тип загрузочного диска каждой ВМ (у каждой ВМ свой отдельный диск): network-hdd дешевле, network-ssd быстрее"
  type        = string
  default     = "network-hdd"
}

variable "cp_preemptible" {
  description = "Прерываемая control plane: дешевле, но Яндекс останавливает ВМ раз в сутки. На защите поставьте false."
  type        = bool
  default     = true
}

variable "worker_preemptible" {
  description = "Прерываемые воркеры: дешевле, но Яндекс останавливает ВМ раз в сутки. На защите поставьте false."
  type        = bool
  default     = true
}
