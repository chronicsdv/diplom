terraform {
  required_version = ">= 1.5.0"

  required_providers {
    yandex = {
      source  = "yandex-cloud/yandex"
      version = ">= 0.120.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.4.0"
    }
  }
}

# Авторизация берётся из переменных окружения (их выставляет Makefile):
#   YC_TOKEN, YC_CLOUD_ID, YC_FOLDER_ID
provider "yandex" {
  zone = var.zone
}
