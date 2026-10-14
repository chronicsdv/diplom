#!/usr/bin/env bash
# Утренний запуск остановленного кластера:
#   запуск ВМ -> обновление terraform.tfvars + IP в Terraform
#   -> обновление kubeconfig -> проверка кластера -> ссылка на сайт.
#
# Запуск из корня репозитория:
#   ./start.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$ROOT/terraform"
TFVARS="$TF_DIR/terraform.tfvars"

log()  { printf '\n\033[1;34m>>> %s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m!!! %s\033[0m\n' "$*"; }
die()  { printf '\033[1;31mERROR: %s\033[0m\n' "$*" >&2; exit 1; }

# ---------- проверка необходимых команд ----------
for cmd in yc terraform kubectl curl python3; do
  command -v "$cmd" >/dev/null || die "Не найдена команда: $cmd"
done

[ -f "$TFVARS" ] || die "Не найден файл $TFVARS"

# ---------- доступ к облаку ----------
export YC_TOKEN="$(yc iam create-token)"
export YC_CLOUD_ID="$(yc config get cloud-id)"
export YC_FOLDER_ID="$(yc config get folder-id)"

[ -n "$YC_TOKEN" ]     || die "Не удалось получить токен yc"
[ -n "$YC_CLOUD_ID" ]  || die "yc: пустой cloud-id (yc config set cloud-id ...)"
[ -n "$YC_FOLDER_ID" ] || die "yc: пустой folder-id (yc config set folder-id ...)"

# ---------- текущий внешний IP ----------
MY_IP="$(curl -4 -s --max-time 10 ifconfig.me || true)"

[[ "$MY_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
  || die "Не удалось определить внешний IPv4 (получено: '${MY_IP}')"

log "Ваш внешний IP для SSH: ${MY_IP}"

# ---------- обновление terraform.tfvars ----------
log "Обновляю terraform.tfvars"

python3 - "$TFVARS" "$MY_IP" <<'PY'
import re
import sys

path = sys.argv[1]
ip = sys.argv[2]

with open(path, "r", encoding="utf-8") as f:
    content = f.read()

new_line = f'allowed_ssh_cidrs = ["{ip}/32"]'

pattern = r'(?m)^[ \t]*allowed_ssh_cidrs[ \t]*=.*$'

if not re.search(pattern, content):
    print("Не найден параметр allowed_ssh_cidrs в terraform.tfvars", file=sys.stderr)
    sys.exit(1)

content = re.sub(pattern, new_line, content, count=1)

with open(path, "w", encoding="utf-8") as f:
    f.write(content)

print(new_line)
PY

# ---------- 1. запуск ВМ ----------
log "Запускаю ВМ"

NAMES="$(
  terraform -chdir="$TF_DIR" output -json 2>/dev/null |
  python3 -c '
import json
import sys

data = json.load(sys.stdin)

for output_name in ("control_plane_ips", "worker_ips"):
    value = data[output_name]["value"]
    print(*value.keys(), sep="\n")
'
)"

[ -n "$NAMES" ] \
  || die "Не удалось получить имена ВМ из Terraform. Выполняли ли вы terraform apply раньше?"

for n in $NAMES; do
  echo "  $n"
  yc compute instance start "$n" >/dev/null 2>&1 \
    || echo "    (уже запущена или запускается)"
done

echo "Жду 60 секунд, пока ВМ получат адреса..."
sleep 60

# ---------- 2. Terraform: новые IP, hosts.ini, api-cert.yml ----------
log "Terraform: обновляю адреса"

terraform -chdir="$TF_DIR" init -input=false >/dev/null

terraform -chdir="$TF_DIR" plan \
  -input=false \
  -out=tfplan

# Защита:
# ВМ и сеть пересоздавать/удалять нельзя.
# Допустимы изменение SSH Security Group и локальных файлов.
terraform -chdir="$TF_DIR" show -json tfplan |
python3 -c '
import json
import sys

plan = json.load(sys.stdin)

bad = [
    c["address"]
    for c in plan.get("resource_changes", [])
    if "delete" in c["change"]["actions"]
    and not c["type"].startswith("local_")
]

if bad:
    print(
        "ОСТАНОВКА: план удаляет/пересоздаёт ресурсы: "
        + ", ".join(bad)
    )
    sys.exit(1)
' || {
  rm -f "$TF_DIR/tfplan"
  die "План опасен, ничего не применено. Проверьте вывод plan выше."
}

terraform -chdir="$TF_DIR" apply -input=false tfplan

rm -f "$TF_DIR/tfplan"

# ---------- 3. kubeconfig ----------
log "Обновляю kubeconfig"

API="$(terraform -chdir="$TF_DIR" output -raw kube_api_endpoint)"

CLUSTER="$(
  kubectl config view --minify -o jsonpath='{.clusters[0].name}'
)"

[ -n "$CLUSTER" ] \
  || die "В ~/.kube/config не найден кластер"

# tls-server-name:
# сертификат Kubernetes API содержит имя "kubernetes",
# поэтому проверяем TLS по имени, а не по новому публичному IP.
kubectl config set-cluster "$CLUSTER" \
  --server="$API" \
  --tls-server-name=kubernetes >/dev/null

echo "API: $API"

# ---------- 4. ожидание кластера ----------
log "Жду, пока кластер ответит (до 10 минут)"

ready=0

for i in $(seq 1 60); do
  if kubectl get nodes >/dev/null 2>&1; then
    ready=1
    break
  fi

  echo "  попытка $i/60: API ещё недоступен..."
  sleep 10
done

[ "$ready" = 1 ] \
  || die "API не отвечает. Проверьте: ssh на control plane и 'sudo systemctl status kubelet'"

kubectl wait \
  --for=condition=Ready \
  nodes \
  --all \
  --timeout=300s \
  || warn "Не все ноды стали Ready за 5 минут"

# ---------- состояние кластера ----------
log "Состояние кластера"

kubectl get nodes

echo
echo "Поды не в статусе Running (в первые минуты это нормально):"

kubectl get pods -A --no-headers |
  grep -v ' Running ' ||
  echo "  все поды Running"

# ---------- ссылка на сайт ----------
WORKER_IP="$(
  terraform -chdir="$TF_DIR" output -json worker_ips |
  python3 -c '
import json
import sys

data = json.load(sys.stdin)
print(next(iter(data.values())))
'
)"

log "Готово. Сайт: http://${WORKER_IP}/"