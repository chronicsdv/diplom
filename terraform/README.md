# Terraform: инфраструктура Craftista в Яндекс Облаке

Создаёт: сеть, подсеть, security group, N control plane и M воркеров (Ubuntu 24.04)
и файл `ansible/inventory/hosts.ini` для Kubespray.

## Подготовка (один раз, WSL2)
1. Установить Terraform и `yc` CLI, выполнить `yc init`.
2. Если Terraform/провайдер не скачиваются, создать `~/.terraformrc`:
   ```
   provider_installation {
     network_mirror {
       url     = "https://terraform-mirror.yandexcloud.net/"
       include = ["registry.terraform.io/*/*"]
     }
     direct {
       exclude = ["registry.terraform.io/*/*"]
     }
   }
   ```
3. SSH-ключ: `ssh-keygen -t ed25519 -f ~/.ssh/craftista -N ""`
4. `cp terraform.tfvars.example terraform.tfvars` и вписать свой внешний IP (`curl ifconfig.me`).

## Авторизация (в каждой новой сессии терминала; токен живёт 12 часов)
```
export YC_TOKEN=$(yc iam create-token)
export YC_CLOUD_ID=$(yc config get cloud-id)
export YC_FOLDER_ID=$(yc config get folder-id)
```

## Запуск
```
cd terraform
terraform init
terraform plan
terraform apply
terraform destroy
```

## Прерываемые ВМ (preemptible)
Яндекс останавливает такие ВМ максимум через 24 часа, публичный IP при этом меняется.
После `yc compute instance start <имя>` выполните `terraform apply -refresh-only`,
чтобы `hosts.ini` обновился. На защите поставьте в `terraform.tfvars`:
`cp_preemptible = false`, `worker_preemptible = false`.
