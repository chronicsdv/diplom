#!/usr/bin/env bash
# Поднимает всё с нуля одной командой:
#   Vagrant (ВМ в Hyper-V на Windows) -> Ansible/Kubespray (Kubernetes) -> kubeconfig -> стек
#
# Запуск из корня репозитория (Windows Terminal должен быть открыт от администратора):
#   ./up.sh              полный цикл
#   ./up.sh kubeconfig   только обновить ~/.kube/config
#   ./up.sh stack        только поставить стек (Traefik, Argo CD, мониторинг, ELK)
#
# Скрипт идемпотентный: при ошибке можно просто запустить его ещё раз.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
KUBESPRAY_TAG="${KUBESPRAY_TAG:-v2.32.0}"   # версия Kubespray зафиксирована для воспроизводимости
CLUSTER_ATTEMPTS="${CLUSTER_ATTEMPTS:-3}"   # попыток cluster.yml (бывают таймауты скачивания)
VAGRANT_WIN_DIR="${VAGRANT_WIN_DIR:-D:\\vagrant-ubuntu}"   # Windows-папка с Vagrantfile
INVENTORY="$ROOT/ansible/inventory/hosts.ini"             # статический inventory

# локальные секреты (файл в git не попадает)
if [ -f "$ROOT/.secrets.env" ]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.secrets.env"
  set +a
fi

log()  { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# powershell.exe запускаем из /mnt/c, иначе он ругается на UNC-путь \\wsl$
ps() { (cd /mnt/c && powershell.exe -NoProfile -Command "$1"); }

# ---------- kubeconfig ----------
setup_kubeconfig() {
  local src="$ROOT/ansible/inventory/artifacts/admin.conf"
  [ -f "$src" ] || die "Нет $src. Сначала должна успешно отработать установка кластера."

  # IP control plane берём из inventory (строка craftista-cp ... ansible_host=...)
  local cp_ip api
  cp_ip="$(awk '/^craftista-cp[[:space:]]/{for(i=1;i<=NF;i++) if($i ~ /^ansible_host=/){sub("ansible_host=","",$i); print $i}}' "$INVENTORY")"
  [ -n "$cp_ip" ] || die "Не нашёл craftista-cp в $INVENTORY"
  api="https://${cp_ip}:6443"

  mkdir -p "$HOME/.kube"
  if [ -f "$HOME/.kube/config" ] && [ ! -f "$HOME/.kube/config.bak" ]; then
    cp "$HOME/.kube/config" "$HOME/.kube/config.bak"   # один раз сохраняем старый конфиг
  fi
  cp "$src" "$HOME/.kube/config"
  sed -i "s#server: .*#server: ${api}#" "$HOME/.kube/config"
  chmod 600 "$HOME/.kube/config"
  log "kubeconfig обновлён, API: ${api}"
}

if [ "${1:-}" = "kubeconfig" ]; then
  setup_kubeconfig
  kubectl get nodes
  exit 0
fi

if [ "${1:-}" = "stack" ]; then
  "$ROOT/bootstrap/install-stack.sh"
  exit 0
fi

# ---------- проверки ----------
for cmd in git python3 powershell.exe; do
  command -v "$cmd" >/dev/null || die "Не найдена команда: $cmd"
done
[ -f "$HOME/.ssh/craftista" ] || die "Нет SSH-ключа ~/.ssh/craftista"
[ -f "$INVENTORY" ] || die "Нет inventory: $INVENTORY"

if [ "${SKIP_VMS:-0}" != 1 ]; then
  ps "vagrant --version" >/dev/null 2>&1 || die "На Windows не найден vagrant (установите Vagrant для Windows)"
  is_admin="$(ps "([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)" | tr -d '\r')"
  [ "$is_admin" = "True" ] || die "Откройте Windows Terminal от имени администратора (Hyper-V требует прав)"
fi

# ---------- 1. Ansible + Kubespray ----------
if [ ! -d "$ROOT/ansible/.venv" ] || [ ! -d "$ROOT/ansible/kubespray" ]; then
  log "Устанавливаю Kubespray $KUBESPRAY_TAG и Ansible в venv"
  "$ROOT/ansible/bootstrap-kubespray.sh" "$KUBESPRAY_TAG"
fi
# shellcheck disable=SC1091
source "$ROOT/ansible/.venv/bin/activate"
export ANSIBLE_HOST_KEY_CHECKING=False

# ---------- 2. Vagrant: ВМ в Hyper-V ----------
if [ "${SKIP_VMS:-0}" = 1 ]; then
  warn "SKIP_VMS=1: ВМ не трогаю, считаю что они уже запущены"
else
  log "Vagrant: поднимаю ВМ в Hyper-V ($VAGRANT_WIN_DIR)"
  ps "cd '$VAGRANT_WIN_DIR'; vagrant up --parallel --provider=hyperv; exit \$LASTEXITCODE" \
    || die "vagrant up завершился с ошибкой (смотрите вывод выше)"
fi

# ---------- 3. Ждём SSH на всех нодах ----------
log "Жду доступности нод по SSH"
cd "$ROOT/ansible"
ready=0
for i in $(seq 1 30); do
  if ansible -i "$INVENTORY" all -m ping -o >/dev/null 2>&1; then ready=1; break; fi
  echo "  попытка $i/30: ноды ещё не отвечают, жду 10 с..."
  sleep 10
done
[ "$ready" = 1 ] || die "Ноды не ответили по SSH за 5 минут (проверьте IP/MAC и резервирование в роутере)"

# ---------- 4. Подготовка нод ----------
log "Ansible: подготовка нод"
ansible-playbook -i "$INVENTORY" prepare.yml

# ---------- 5. Kubernetes ----------
log "Kubespray: устанавливаю кластер (около 15-20 минут)"
ok=0
for attempt in $(seq 1 "$CLUSTER_ATTEMPTS"); do
  if (cd kubespray && ansible-playbook -i "$INVENTORY" --become cluster.yml); then
    ok=1; break
  fi
  warn "cluster.yml завершился с ошибкой (попытка $attempt/$CLUSTER_ATTEMPTS), повторяю"
done
[ "$ok" = 1 ] || die "Не удалось установить кластер. Смотрите блок fatal: в выводе выше."

# ---------- 6. kubeconfig ----------
setup_kubeconfig
kubectl get nodes

# ---------- 7. Стек: Traefik, Argo CD, мониторинг, ELK ----------
if [ "${INSTALL_STACK:-1}" = 1 ]; then
  "$ROOT/bootstrap/install-stack.sh"
else
  warn "INSTALL_STACK=0: стек не ставлю (позже: ./up.sh stack)"
fi
log "Готово"
