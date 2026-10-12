variable "hyperv_user" {
  description = "Локальный администратор Windows для WinRM"
  type        = string
  default     = "tfhyperv"
}

variable "hyperv_password" {
  description = "Пароль hyperv_user (задаётся через TF_VAR_hyperv_password или вводится в up.sh)"
  type        = string
  sensitive   = true
}

variable "name_prefix" {
  type    = string
  default = "craftista"
}

variable "switch_name" {
  description = "Внешний виртуальный коммутатор Hyper-V (мост в домашнюю сеть)"
  type        = string
  default     = "k8s-external"
}

variable "template_vhd" {
  description = "Шаблон диска Ubuntu 24.04 (фиксированный VHDX, копия остаётся фиксированной)"
  type        = string
  default     = "D:\\hyperv\\templates\\ubuntu-2404-k8s-fixed.vhdx"
}

variable "vm_path" {
  type    = string
  default = "D:\\hyperv\\vms"
}

variable "disk_path" {
  type    = string
  default = "D:\\hyperv\\disks"
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/craftista"
}

variable "control_plane_count" {
  description = "1 на разработке, 3 на защите (нечётное!)"
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
