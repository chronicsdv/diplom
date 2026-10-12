# Terraform: Craftista на локальном Hyper-V

Альтернатива Яндекс-варианту (`terraform/`): те же ВМ (control plane + воркеры, Ubuntu 24.04),
тот же `hosts.ini` для Kubespray, но на Windows-хосте с Hyper-V. Всё остальное
(Kubespray, Ansible, Argo CD, Helm) не меняется.

## Требования к хосту

- Windows 11 Pro/Enterprise с включённым Hyper-V, права администратора.
- От 32 ГБ RAM (4 ВМ по 4 ГБ = 16 ГБ). 4 ВМ с фиксированными дисками по 30 ГБ = 120 ГБ
  плюс шаблон 30 ГБ: на диске `D:` нужно около 150 ГБ свободного места.
- WSL2 (Ubuntu) с Terraform, Ansible (ставит `up.sh`) и ключом `~/.ssh/craftista`.

## Подготовка хоста (один раз, PowerShell от администратора)

1. **Внешний свитч** (мост в домашнюю сеть, ВМ получают адреса от роутера):

   ```powershell
   New-VMSwitch -Name "k8s-external" -NetAdapterName "Ethernet" -AllowManagementOS $true
   ```

2. **Папки и пути Hyper-V:**

   ```powershell
   mkdir D:\hyperv\vms, D:\hyperv\disks, D:\hyperv\templates -Force
   Set-VMHost -VirtualMachinePath D:\hyperv\vms -VirtualHardDiskPath D:\hyperv\disks
   ```

3. **Шаблон ВМ.** Образ Ubuntu 24.04 создан скриптом `New-HyperVCloudImageVM.ps1`
   (github.com/schtritoff/hyperv-vm-provisioning) с cloud-init: пользователь `ubuntu`,
   публичный ключ `~/.ssh/craftista.pub`, пакет `linux-cloud-tools-virtual` (без него Hyper-V не
   видит IP гостя). Перед клонированием внутри ВМ:

   - заменить `/etc/netplan/50-cloud-init.yaml` на общий `01-dhcp.yaml`
     (`match: name: "e*"`, `dhcp4: true`, `dhcp-identifier: mac`), иначе сеть привязана к MAC шаблона;
   - выполнить `cloud-init clean --logs`, `touch /etc/cloud/cloud-init.disabled`,
     `truncate -s 0 /etc/machine-id`, `rm -f /var/lib/dbus/machine-id`, выключить ВМ
     и больше не запускать.

   Затем диск шаблона превращается в фиксированный (копии Terraform остаются фиксированными):

   ```powershell
   Convert-VHD -Path <шаблон>.vhdx -DestinationPath D:\hyperv\templates\ubuntu-2404-k8s-fixed.vhdx -VHDType Fixed
   ```

4. **WinRM для Terraform** (только локально, наружу не открыт): локальный администратор `tfhyperv`,
   `Enable-PSRemoting -SkipNetworkProfileCheck -Force`, HTTPS-слушатель на 5986 с самоподписанным
   сертификатом `localhost`, правила файрвола для HTTP 5985 выключены.

5. **WSL:** в `%USERPROFILE%\.wslconfig` секция `[wsl2]` с `networkingMode=mirrored`,
   затем `wsl --shutdown`. Так WSL видит WinRM на `127.0.0.1:5986` и ВМ в локальной сети.

6. В роутере желательно зарезервировать IP для MAC-адресов ВМ: у control plane
   `00:15:5D:0A:01:xx`, у воркеров `00:15:5D:0A:02:xx` (они заданы в Terraform).

## Запуск

Из корня репозитория (в WSL):

```bash
INFRA=hyperv ./up.sh
```

Скрипт спросит пароль `tfhyperv` (или возьмёт его из `TF_VAR_hyperv_password`), создаст ВМ,
поставит Kubernetes через Kubespray и обновит kubeconfig. Первый запуск долгий: копируются
фиксированные диски.

## Особенности

- Провайдер `taliesins/hyperv` работает через WinRM, поэтому `plan` и `apply` идут медленнее,
  чем в облаке. Terraform нужно запускать на машине, где доступен WinRM хоста.
- Сертификат WinRM самоподписанный (`insecure = true`), это допустимо только для localhost.
- Кластер доступен из домашней сети. GitHub-раннеры до него не достают (деплой через Argo CD
  работает, он забирает манифесты из Git сам).
