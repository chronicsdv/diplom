#!/usr/bin/env bash
# Запуск остановленного кластера на Hyper-V:
#   запуск ВМ (через WinRM) -> ожидание SSH -> Terraform (актуальные IP, hosts.ini)
#   -> kubeconfig -> проверка кластера -> ссылка на сайт.
#
# Запуск из корня репозитория (в WSL):
#   ./start-hyperv.sh
# Пароль пользователя tfhyperv берётся из TF_VAR_hyperv_password или вводится вручную.

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$ROOT/terraform-hyperv"
HYPERV_USER="${TF_VAR_hyperv_user:-tfhyperv}"

log()  { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

trap 'rm -f "$TF_DIR/tfplan" "$TF_DIR/tfstart"' EXIT

# ---------- проверки ----------
for cmd in terraform kubectl python3 powershell.exe iconv base64; do
  command -v "$cmd" >/dev/null || die "Не найдена команда: $cmd"
done
[ -f "$TF_DIR/terraform.tfstate" ] \
  || die "Нет $TF_DIR/terraform.tfstate: кластер ещё не создавали (./up.sh с INFRA=hyperv)"

if [ -z "${TF_VAR_hyperv_password:-}" ]; then
  read -rsp "Пароль пользователя $HYPERV_USER: " TF_VAR_hyperv_password; echo
fi
export TF_VAR_hyperv_password TF_VAR_hyperv_user="$HYPERV_USER"

# ---------- имена и последние известные IP нод (из state) ----------
NODES="$(
  terraform -chdir="$TF_DIR" output -json | python3 -c '
import json, sys
d = json.load(sys.stdin)
for k in ("control_plane_ips", "worker_ips"):
    for name, ip in d[k]["value"].items():
        print(name, ip)
'
)" || die "Не удалось прочитать ноды из Terraform state"
[ -n "$NODES" ] || die "В Terraform state нет нод"

VM_NAMES="$(printf '%s\n' "$NODES" | awk '{print $1}' | paste -sd, -)"
export VM_NAMES
export WSLENV="${WSLENV:+$WSLENV:}TF_VAR_hyperv_password:TF_VAR_hyperv_user:VM_NAMES"

# ---------- 1. запуск ВМ через провайдер Terraform (тот же вход, что в plan/apply) ----------
log "Запускаю ВМ: ${VM_NAMES//,/ }"
terraform -chdir="$TF_DIR" init -input=false >/dev/null
terraform -chdir="$TF_DIR" plan -input=false -out=tfstart \
  -target=hyperv_machine_instance.control_plane \
  -target=hyperv_machine_instance.worker \
  || die "Не удалось построить план запуска ВМ"
# ВМ и диски пересоздавать/удалять нельзя
terraform -chdir="$TF_DIR" show -json tfstart | python3 -c '
import json, sys
plan = json.load(sys.stdin)
bad = [c["address"] for c in plan.get("resource_changes", [])
       if "delete" in c["change"]["actions"]]
if bad:
    print("ОСТАНОВКА: план удаляет или пересоздаёт ресурсы: " + ", ".join(bad))
    sys.exit(1)
' || die "План запуска опасен, ничего не применено. Проверьте вывод plan выше."
terraform -chdir="$TF_DIR" apply -input=false tfstart \
  || die "Не удалось запустить ВМ через Terraform"

# ---------- 2. ждём SSH на всех нодах ----------
log "Жду SSH на нодах (до 5 минут на каждую)"
while read -r name ip; do
  printf '  %s (%s): ' "$name" "$ip"
  ok=0
  for _ in $(seq 1 60); do
    if timeout 3 bash -c "exec 3<>/dev/tcp/$ip/22" 2>/dev/null; then ok=1; break; fi
    sleep 5
  done
  if [ "$ok" = 1 ]; then echo "отвечает"; else echo "нет ответа"; die "$name не отвечает по SSH"; fi
done <<< "$NODES"

# ---------- 3. Terraform: актуальные IP, hosts.ini, api-cert.yml ----------
log "Terraform: проверяю адреса (WinRM работает небыстро)"
terraform -chdir="$TF_DIR" init -input=false >/dev/null

planned=0
rc=0
for attempt in 1 2 3 4 5 6; do
  rc=0
  terraform -chdir="$TF_DIR" plan -input=false -detailed-exitcode -out=tfplan || rc=$?
  if [ "$rc" = 0 ] || [ "$rc" = 2 ]; then planned=1; break; fi
  warn "plan не прошёл (попытка $attempt/6): Hyper-V ещё не отдал IP. Жду 20 секунд..."
  sleep 20
done
[ "$planned" = 1 ] || die "terraform plan не удался. Проверьте вывод выше."

if [ "$rc" = 2 ]; then
  # ВМ и диски пересоздавать/удалять нельзя (допустимы только локальные файлы)
  terraform -chdir="$TF_DIR" show -json tfplan | python3 -c '
import json, sys
plan = json.load(sys.stdin)
bad = [c["address"] for c in plan.get("resource_changes", [])
       if "delete" in c["change"]["actions"] and not c["type"].startswith("local_")]
if bad:
    print("ОСТАНОВКА: план удаляет или пересоздаёт ресурсы: " + ", ".join(bad))
    sys.exit(1)
' || die "План опасен, ничего не применено. Проверьте вывод plan выше."
  terraform -chdir="$TF_DIR" apply -input=false tfplan
else
  echo "Изменений нет, адреса прежние."
fi

# ---------- 4. kubeconfig ----------
log "Обновляю kubeconfig"
API="$(terraform -chdir="$TF_DIR" output -raw kube_api_endpoint)"
CLUSTER="$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')"
[ -n "$CLUSTER" ] || die "В ~/.kube/config не найден кластер (выполните ./up.sh kubeconfig)"
# tls-server-name: сертификат API содержит имя "kubernetes", так проверка не зависит от IP
kubectl config set-cluster "$CLUSTER" --server="$API" --tls-server-name=kubernetes >/dev/null
echo "API: $API"

# ---------- 5. ждём кластер ----------
log "Жду, пока API ответит (до 10 минут)"
ready=0
for i in $(seq 1 60); do
  if kubectl get nodes >/dev/null 2>&1; then ready=1; break; fi
  echo "  попытка $i/60: API ещё недоступен..."
  sleep 10
done
[ "$ready" = 1 ] || die "API не отвечает. Проверьте: ssh на control plane и 'sudo systemctl status kubelet'"

kubectl wait --for=condition=Ready nodes --all --timeout=300s \
  || warn "Не все ноды стали Ready за 5 минут"

log "Состояние кластера"
kubectl get nodes
echo
echo "Поды не в статусе Running (в первые минуты после старта это нормально):"
kubectl get pods -A --no-headers | grep -v ' Running ' || echo "  все поды Running"

WORKER_IP="$(
  terraform -chdir="$TF_DIR" output -json worker_ips | python3 -c '
import json, sys
print(next(iter(json.load(sys.stdin).values())))
'
)"
log "Готово. Сайт: http://${WORKER_IP}/"
