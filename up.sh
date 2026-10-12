#!/usr/bin/env bash
# Поднимает всё с нуля одной командой:
#   Terraform (ВМ в Яндекс Облаке) -> Ansible/Kubespray (Kubernetes) -> kubeconfig
#
# Запуск из корня репозитория:
#   ./up.sh              полный цикл
#   ./up.sh kubeconfig   только обновить ~/.kube/config (например, после смены IP)
#
# Скрипт идемпотентный: при ошибке можно просто запустить его ещё раз.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
KUBESPRAY_TAG="${KUBESPRAY_TAG:-v2.32.0}"   # версия Kubespray зафиксирована для воспроизводимости
CLUSTER_ATTEMPTS="${CLUSTER_ATTEMPTS:-3}"   # попыток cluster.yml (бывают таймауты скачивания)
INFRA="${INFRA:-yandex}"                    # yandex | hyperv (INFRA=hyperv ./up.sh)
case "$INFRA" in
  yandex) TF_DIR="$ROOT/terraform" ;;
  hyperv) TF_DIR="$ROOT/terraform-hyperv" ;;
  *) echo "INFRA должен быть yandex или hyperv" >&2; exit 1 ;;
esac

log()  { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- kubeconfig ----------
setup_kubeconfig() {
  local src="$ROOT/ansible/inventory/artifacts/admin.conf"
  [ -f "$src" ] || die "Нет $src. Сначала должна успешно отработать установка кластера."
  local api
  api="$(terraform -chdir="$TF_DIR" output -raw kube_api_endpoint)"

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

# ---------- проверки ----------
cmds="terraform git python3"
if [ "$INFRA" = yandex ]; then cmds="$cmds yc"; fi
for cmd in $cmds; do
  command -v "$cmd" >/dev/null || die "Не найдена команда: $cmd"
done
if [ "$INFRA" = yandex ]; then
  [ -f "$ROOT/terraform/terraform.tfvars" ] || die "Создайте terraform/terraform.tfvars (см. terraform.tfvars.example)"
fi
[ -f "$HOME/.ssh/craftista" ] || die "Нет SSH-ключа ~/.ssh/craftista"

# ---------- 1. Ansible + Kubespray (не зависит от инфраструктуры) ----------
if [ ! -d "$ROOT/ansible/.venv" ] || [ ! -d "$ROOT/ansible/kubespray" ]; then
  log "Устанавливаю Kubespray $KUBESPRAY_TAG и Ansible в venv"
  "$ROOT/ansible/bootstrap-kubespray.sh" "$KUBESPRAY_TAG"
fi
# shellcheck disable=SC1091
source "$ROOT/ansible/.venv/bin/activate"
export ANSIBLE_HOST_KEY_CHECKING=False

# ---------- 2. Terraform ----------
log "Terraform ($INFRA): создаю инфраструктуру"
if [ "$INFRA" = yandex ]; then
  export YC_TOKEN="$(yc iam create-token)"
  export YC_CLOUD_ID="$(yc config get cloud-id)"
  export YC_FOLDER_ID="$(yc config get folder-id)"
elif [ -z "${TF_VAR_hyperv_password:-}" ]; then
  read -rsp "Пароль пользователя tfhyperv: " TF_VAR_hyperv_password; echo
  export TF_VAR_hyperv_password
fi
terraform -chdir="$TF_DIR" init -input=false
terraform -chdir="$TF_DIR" apply -auto-approve -input=false

# ---------- 3. Ждём SSH на всех нодах ----------
log "Жду доступности нод по SSH"
cd "$ROOT/ansible"
ready=0
for i in $(seq 1 30); do
  if ansible -i inventory/hosts.ini all -m ping -o >/dev/null 2>&1; then ready=1; break; fi
  echo "  попытка $i/30: ноды ещё не отвечают, жду 10 с..."
  sleep 10
done
[ "$ready" = 1 ] || die "Ноды не ответили по SSH за 5 минут"

# ---------- 4. Подготовка нод ----------
log "Ansible: подготовка нод"
ansible-playbook -i inventory/hosts.ini prepare.yml

# ---------- 5. Kubernetes ----------
log "Kubespray: устанавливаю кластер (около 15-20 минут)"
ok=0
for attempt in $(seq 1 "$CLUSTER_ATTEMPTS"); do
  if (cd kubespray && ansible-playbook -i ../inventory/hosts.ini --become cluster.yml); then
    ok=1; break
  fi
  warn "cluster.yml завершился с ошибкой (попытка $attempt/$CLUSTER_ATTEMPTS), повторяю"
done
[ "$ok" = 1 ] || die "Не удалось установить кластер. Смотрите блок fatal: в выводе выше."

# ---------- 6. kubeconfig ----------
setup_kubeconfig
kubectl get nodes
log "Готово"
