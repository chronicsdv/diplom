terraform {
  required_version = ">= 1.5.0"

  required_providers {
    hyperv = {
      source  = "taliesins/hyperv"
      version = "~> 1.2.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
  }
}

# Hyper-V управляется через WinRM (HTTPS, самоподписанный сертификат, только localhost).
# Копирование фиксированных дисков по 30 ГБ долгое, поэтому таймаут большой.
provider "hyperv" {
  host     = "localhost"
  port     = 5986
  https    = true
  insecure = true
  use_ntlm = true
  user     = var.hyperv_user
  password = var.hyperv_password
  timeout  = "1200s"
}
