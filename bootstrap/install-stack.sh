#!/usr/bin/env bash
# Ставит на готовый кластер: Traefik, Argo CD (+ приложение), мониторинг, логи (Loki + Alloy; ELK как запасной вариант).
# Идемпотентен: helm upgrade --install, существующие секреты не перезаписываются.
#
# Запуск из корня репозитория:
#   bootstrap/install-stack.sh        (или ./up.sh stack)
#
# Переменные окружения:
#   ONLY                какие компоненты ставить, через пробел: traefik argocd app monitoring loki elk
#                       (пусто = все). Пример: ONLY="monitoring loki" ./up.sh stack
#   LOGGING_STACK       loki (по умолчанию) или elk: какой стек логов ставить
#   TELEGRAM_CHAT_ID    чат для алертов (обязателен для мониторинга; спросит, если не задан)
#   TELEGRAM_BOT_TOKEN  токен бота (нужен, только пока нет секрета alertmanager-telegram)
#   SKIP_MONITORING=1   не ставить мониторинг
#   SKIP_LOGGING=1      не ставить Loki + Alloy
#   SKIP_ELK=1          не ставить ELK (при LOGGING_STACK=elk)
#   LOKI_CHART_VERSION / ALLOY_CHART_VERSION   версии чартов (пусто = последняя; после первой удачной установки закрепите)
#   TRAEFIK_VALUES / ARGOCD_VALUES / MONITORING_VALUES   пути к values-файлам
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TRAEFIK_VALUES="${TRAEFIK_VALUES:-$ROOT/bootstrap/traefik-values.yaml}"
ARGOCD_VALUES="${ARGOCD_VALUES:-$ROOT/bootstrap/argocd-values.yaml}"
MONITORING_VALUES="${MONITORING_VALUES:-$ROOT/bootstrap/monitoring-values.yaml}"
ELK_DIR="$ROOT/bootstrap/elk"
LOKI_VALUES="${LOKI_VALUES:-$ROOT/bootstrap/loki-values.yaml}"
ALLOY_VALUES="${ALLOY_VALUES:-$ROOT/bootstrap/alloy-values.yaml}"
LOGGING_STACK="${LOGGING_STACK:-loki}"
LOKI_CHART_VERSION="${LOKI_CHART_VERSION:-19.0.0}"
ALLOY_CHART_VERSION="${ALLOY_CHART_VERSION:-1.14.0}"

# версии чартов зафиксированы для воспроизводимости
TRAEFIK_CHART_VERSION="${TRAEFIK_CHART_VERSION:-41.7.1}"
ARGOCD_CHART_VERSION="${ARGOCD_CHART_VERSION:-10.10.3}"
MONITORING_CHART_VERSION="${MONITORING_CHART_VERSION:-92.7.0}"

# выбор компонентов: ONLY пусто = всё
ONLY="${ONLY:-}"
want() { [ -z "$ONLY" ] || [[ " $ONLY " == *" $1 "* ]]; }

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

# ---------- проверки ----------
for cmd in kubectl helm openssl; do
  command -v "$cmd" >/dev/null || die "Не найдена команда: $cmd"
done
if want monitoring && [ "${SKIP_MONITORING:-0}" != 1 ]; then
  command -v envsubst >/dev/null || die "Не найден envsubst (sudo apt install gettext-base)"
fi
kubectl get nodes >/dev/null 2>&1 || die "Кластер недоступен (kubectl get nodes). Сначала ./up.sh kubeconfig"
[ -f "$TRAEFIK_VALUES" ] || die "Нет $TRAEFIK_VALUES"
[ -f "$ARGOCD_VALUES" ]  || die "Нет $ARGOCD_VALUES (укажите путь в ARGOCD_VALUES=...)"
[ -f "$ROOT/argocd/application.yaml" ] || die "Нет argocd/application.yaml"

[ -z "$ONLY" ] || log "Выбранные компоненты: $ONLY"

ensure_ns() { kubectl create namespace "$1" --dry-run=client -o yaml | kubectl apply -f - >/dev/null; }

log "Helm-репозитории"
helm repo add traefik https://traefik.github.io/charts --force-update >/dev/null
helm repo add argo https://argoproj.github.io/argo-helm --force-update >/dev/null
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts --force-update >/dev/null
helm repo add grafana https://grafana.github.io/helm-charts --force-update >/dev/null
helm repo update >/dev/null

# ---------- 1. Traefik ----------
if want traefik; then
  log "Traefik"
  helm upgrade --install traefik traefik/traefik --version "$TRAEFIK_CHART_VERSION" -n traefik --create-namespace \
    -f "$TRAEFIK_VALUES" --wait --timeout 5m
fi

# ---------- 2. Argo CD ----------
if want argocd; then
  log "Argo CD"
  ensure_ns argocd
  if ! kubectl -n argocd get secret argocd-notifications-secret >/dev/null 2>&1; then
    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
      [ -t 0 ] || die "Задайте TELEGRAM_BOT_TOKEN (нужен для уведомлений Argo CD)"
      read -rsp "Токен Telegram-бота: " TELEGRAM_BOT_TOKEN; echo
    fi
    kubectl -n argocd create secret generic argocd-notifications-secret \
      --from-literal=telegram-token="$TELEGRAM_BOT_TOKEN" >/dev/null
    echo "  секрет argocd-notifications-secret создан"
  fi
  helm upgrade --install argocd argo/argo-cd --version "$ARGOCD_CHART_VERSION" -n argocd --create-namespace \
    -f "$ARGOCD_VALUES" --wait --timeout 10m
fi

# ---------- 3. Приложение ----------
if want app; then
  log "Приложение Craftista (секрет БД и Argo CD Application)"
  ensure_ns craftista
  if ! kubectl -n craftista get secret craftista-db >/dev/null 2>&1; then
    DB_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
    kubectl -n craftista create secret generic craftista-db \
      --from-literal=DB_NAME=catalogue \
      --from-literal=DB_USER=devops \
      --from-literal=DB_PASSWORD="$DB_PASSWORD" >/dev/null
    echo "  секрет craftista-db создан"
  else
    echo "  секрет craftista-db уже есть, не трогаю"
  fi
  kubectl apply -f "$ROOT/argocd/application.yaml"
  if [ -n "${TELEGRAM_CHAT_ID:-}" ]; then
    for t in on-deployed on-sync-failed on-health-degraded; do
      kubectl -n argocd annotate application craftista --overwrite \
        "notifications.argoproj.io/subscribe.${t}.telegram=${TELEGRAM_CHAT_ID}" >/dev/null
    done
  else
    warn "TELEGRAM_CHAT_ID не задан: уведомления Argo CD не подписаны"
  fi
fi

# ---------- 4. Мониторинг ----------
if want monitoring && [ "${SKIP_MONITORING:-0}" != 1 ]; then
  log "Мониторинг (kube-prometheus-stack)"
  [ -f "$MONITORING_VALUES" ] || die "Нет $MONITORING_VALUES"
  ensure_ns monitoring
  if ! kubectl -n monitoring get secret alertmanager-telegram >/dev/null 2>&1; then
    if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
      [ -t 0 ] || die "Задайте TELEGRAM_BOT_TOKEN (секрета alertmanager-telegram ещё нет)"
      read -rsp "Токен Telegram-бота: " TELEGRAM_BOT_TOKEN; echo
    fi
    kubectl -n monitoring create secret generic alertmanager-telegram \
      --from-literal=token="$TELEGRAM_BOT_TOKEN" >/dev/null
    echo "  секрет alertmanager-telegram создан"
  fi
  if [ -z "${TELEGRAM_CHAT_ID:-}" ]; then
    [ -t 0 ] || die "Задайте TELEGRAM_CHAT_ID"
    read -rp "Telegram chat_id: " TELEGRAM_CHAT_ID
  fi
  export TELEGRAM_CHAT_ID
  envsubst < "$MONITORING_VALUES" | helm upgrade --install monitoring \
    prometheus-community/kube-prometheus-stack --version "$MONITORING_CHART_VERSION" \
    -n monitoring -f - --wait --timeout 15m
fi

# ---------- 5. Логи: Loki + Alloy ----------
if want loki && [ "$LOGGING_STACK" = loki ] && [ "${SKIP_LOGGING:-0}" != 1 ]; then
  [ -f "$LOKI_VALUES" ]  || die "Нет $LOKI_VALUES"
  [ -f "$ALLOY_VALUES" ] || die "Нет $ALLOY_VALUES"
  log "Loki (хранилище логов)"
  helm upgrade --install loki grafana-community/loki ${LOKI_CHART_VERSION:+--version "$LOKI_CHART_VERSION"} \
    -n logging --create-namespace -f "$LOKI_VALUES" --wait --timeout 10m
  log "Alloy (сбор логов с узлов)"
  helm upgrade --install alloy grafana/alloy ${ALLOY_CHART_VERSION:+--version "$ALLOY_CHART_VERSION"} \
    -n logging -f "$ALLOY_VALUES" --wait --timeout 5m
  helm list -n logging
fi

# ---------- 6. ELK (запасной вариант: LOGGING_STACK=elk) ----------
if want elk && [ "$LOGGING_STACK" = elk ] && [ "${SKIP_ELK:-0}" != 1 ]; then
  log "ELK: ECK-оператор"
  ECK_CHART="$(ls "$ROOT"/bootstrap/charts/eck-operator-*.tgz 2>/dev/null | sort -V | tail -1)"
  [ -n "$ECK_CHART" ] || die "Нет чарта bootstrap/charts/eck-operator-*.tgz"
  helm upgrade --install elastic-operator "$ECK_CHART" -n elastic-system --create-namespace \
    --wait --timeout 5m

  log "ELK: Elasticsearch, Logstash, Kibana, Filebeat (первый запуск тянет образы, до 15 минут)"
  kubectl apply -k "$ELK_DIR"
  kubectl -n logging wait --for=jsonpath='{.status.phase}'=Ready elasticsearch/logs --timeout=15m \
    || die "Elasticsearch не стал Ready. Смотрите: kubectl -n logging get pods,events"

  log "ELK: хранение логов 3 дня (ILM) и без реплик"
  ES_PASS="$(kubectl -n logging get secret logs-es-elastic-user -o go-template='{{.data.elastic | base64decode}}')"
  es() {
    kubectl -n logging exec logs-es-default-0 -c elasticsearch -- \
      curl -sSk -u "elastic:${ES_PASS}" -H 'Content-Type: application/json' "$@"
  }
  es -XPUT https://localhost:9200/_ilm/policy/logs-3d -d \
    '{"policy":{"phases":{"hot":{"actions":{}},"delete":{"min_age":"3d","actions":{"delete":{}}}}}}'
  echo
  es -XPUT https://localhost:9200/_index_template/logstash-logs -d \
    '{"index_patterns":["logstash-*"],"priority":200,"template":{"settings":{"index.lifecycle.name":"logs-3d","index.number_of_replicas":0}}}'
  echo
fi

# ---------- итог ----------
log "Готово. Что проверить"
kubectl get pods -A --no-headers | grep -vE ' (Running|Completed) ' || echo "  все поды Running/Completed"
cat <<'EOF'

Argo CD:   kubectl -n argocd port-forward svc/argocd-server 8080:443   (https://localhost:8080, admin)
           kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
Grafana:   kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
Логи:      Grafana, Explore, источник Loki, запрос {namespace="craftista"}
           (вариант ELK: kubectl -n logging port-forward svc/kibana-kb-http 5601:5601)
Сайт:      http://<IP любого воркера>/
EOF
