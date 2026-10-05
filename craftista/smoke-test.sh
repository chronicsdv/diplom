#!/usr/bin/env bash
# =====================================================================
# smoke-test.sh — быстрая проверка, что весь Craftista реально работает.
# Запуск (после `docker compose up -d --build`):   ./smoke-test.sh
#
# Наружу открыт только frontend, поэтому проверяем ВСЮ цепочку через него:
# frontend → catalogue / recco / voting. Если ответы приходят — значит
# и сеть, и имена хостов, и сами сервисы работают.
# =====================================================================
set -u

BASE="${BASE_URL:-http://localhost:3000}"   # можно переопределить: BASE_URL=http://host:80 ./smoke-test.sh
FAIL=0

# Ждём, пока frontend начнёт отвечать (до ~90 секунд: JVM у voting стартует долго)
echo "Ожидание frontend на ${BASE} ..."
for i in $(seq 1 45); do
  curl -fsS -o /dev/null "${BASE}/" && break
  sleep 2
  [ "$i" -eq 45 ] && { echo "FAIL: frontend не отвечает"; exit 1; }
done

# check <описание> <путь> <ожидаемая подстрока в ответе>
check() {
  local name="$1" path="$2" expect="$3" body code
  body=$(curl -sS -m 10 -w '\n%{http_code}' "${BASE}${path}" 2>&1)
  code=$(echo "$body" | tail -n1)
  body=$(echo "$body" | sed '$d')
  if [ "$code" = "200" ] && echo "$body" | grep -q "$expect"; then
    echo "OK    ${name}  (${path})"
  else
    echo "FAIL  ${name}  (${path})  HTTP ${code}  ${body:0:120}"
    FAIL=1
  fi
}

check "Главная страница frontend"      "/"                     "html"
check "Catalogue из PostgreSQL (DB)"   "/api/products"         "(DB)"
check "Статус: catalogue"              "/api/service-status"   '"Catalogue":"up"'
check "Статус: recommendation"         "/recommendation-status" '"status":"up"'
check "Статус: voting"                 "/votingservice-status" '"status":"up"'
check "Оригами дня (recommendation)"   "/daily-origami"        "name"

# --- Голосование: проголосовать и убедиться, что счётчик вырос ---
# (сразу после старта voting ещё может не успеть синхронизировать список — пробуем несколько раз)
ok=0
for i in $(seq 1 15); do
  before=$(curl -fsS -m 5 "${BASE}/api/origamis/1/votes" 2>/dev/null) || { sleep 4; continue; }
  curl -fsS -m 5 -X POST "${BASE}/api/origamis/1/vote" -o /dev/null || { sleep 4; continue; }
  after=$(curl -fsS -m 5 "${BASE}/api/origamis/1/votes" 2>/dev/null)
  if [ "${after:-x}" -eq $((before + 1)) ] 2>/dev/null; then ok=1; break; fi
  sleep 4
done
if [ "$ok" -eq 1 ]; then echo "OK    Голосование работает (голосов: ${before} → ${after})"
else echo "FAIL  Голосование не работает"; FAIL=1; fi

echo
echo "Статус healthcheck контейнеров:"
docker compose ps --format 'table {{.Service}}\t{{.Status}}' 2>/dev/null || true

echo
[ "$FAIL" -eq 0 ] && echo "ВСЁ РАБОТАЕТ ✔" || { echo "ЕСТЬ ОШИБКИ ✘  — смотрите: docker compose logs <сервис>"; exit 1; }
