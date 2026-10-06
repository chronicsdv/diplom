# syntax=docker/dockerfile:1.7
# ^ Первая строка — директива парсера. Подключает современный синтаксис Dockerfile
#   (он нужен для кеш-маунтов `RUN --mount=type=cache`, которые ускоряют сборку).

# =====================================================================
# FRONTEND — Node.js + Express + EJS, порт 3000
# Собирается в 2 этапа (multi-stage): сначала ставим зависимости,
# потом собираем минимальный итоговый образ без лишнего мусора.
# =====================================================================

# Версия Node вынесена в ARG: можно сменить при сборке
#   docker build --build-arg NODE_VERSION=24 ...
ARG NODE_VERSION=22
ARG ALPINE_VERSION=3.22

# ---------------------------------------------------------------------
# ЭТАП 1: deps — устанавливаем только production-зависимости
# ---------------------------------------------------------------------
# alpine — маленький базовый образ (~50 МБ вместо ~400 МБ у debian-вариантов)
FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION} AS deps
WORKDIR /app

# Сначала копируем ТОЛЬКО манифесты зависимостей. Пока package.json не менялся,
# Docker берёт этот слой из кеша и не переустанавливает npm-пакеты при правке кода.
# Звёздочка у package-lock.json*: скопировать, только если файл существует
# (в репозитории его сейчас нет — см. комментарий ниже). Одна инструкция = один слой.
COPY package.json package-lock.json* ./

# --mount=type=cache — npm-кеш живёт между сборками, но НЕ попадает в образ.
# --omit=dev      — не ставим mocha/chai/nock (они нужны только для тестов).
# Если lock-файл есть — `npm ci` (воспроизводимая установка ровно тех версий),
# если нет — обычный `npm install`.
# СОВЕТ: закоммитьте package-lock.json, тогда сборки станут детерминированными.
RUN --mount=type=cache,target=/root/.npm \
    if [ -f package-lock.json ]; then \
      npm ci --omit=dev --no-audit --no-fund; \
    else \
      npm install --omit=dev --no-audit --no-fund; \
    fi

# ---------------------------------------------------------------------
# ЭТАП 2: runtime — итоговый образ, который реально запускается
# ---------------------------------------------------------------------
FROM node:${NODE_VERSION}-alpine${ALPINE_VERSION} AS runtime

# OCI-метки: кто собрал, откуда исходники (видно в `docker inspect`, реестрах и сканерах)
LABEL org.opencontainers.image.title="craftista-frontend" \
      org.opencontainers.image.description="Craftista frontend (Node.js/Express)" \
      org.opencontainers.image.source="https://github.com/craftista/craftista" \
      org.opencontainers.image.licenses="Apache-2.0"

# tini — крошечный «init»-процесс. Когда Node запущен как PID 1, он не умеет
# корректно обрабатывать сигналы и «подбирать» зомби-процессы. tini решает это,
# поэтому `docker stop` останавливает контейнер мгновенно, а не через 10 секунд.
RUN apk add --no-cache tini=0.19.0-r3

# NODE_ENV=production — Express и библиотеки включают оптимизации (кеш шаблонов и т.д.)
# PORT — app.js читает process.env.PORT (по умолчанию 3000)
ENV NODE_ENV=production \
    PORT=3000

WORKDIR /app

# Копируем готовые node_modules из первого этапа. --chown отдаёт файлы
# непривилегированному пользователю `node` (он уже есть в образе, uid 1000).
COPY --from=deps --chown=node:node /app/node_modules ./node_modules

# Код приложения — ОДНИМ COPY. Что именно попадёт в образ, решает белый список
# в .dockerignore (app.js, config.json, routes/, views/, public/, package*.json),
# поэтому тесты и README сюда не просочатся.
# Порядок важен: node_modules (меняется редко) — выше, код (меняется часто) — ниже.
COPY --chown=node:node . .

# Запускаем НЕ от root: если в приложении найдут уязвимость,
# у атакующего будет минимум прав внутри контейнера.
USER node

# EXPOSE — документация (какой порт слушает приложение); сам порт не публикует.
EXPOSE 3000

# Проверка здоровья: Docker раз в 30 с дёргает главную страницу.
# Статус контейнера станет "healthy"/"unhealthy" — этим пользуется compose (depends_on).
# wget входит в busybox (curl в alpine нет). start-period — «льготное» время на старт.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD wget -q -O /dev/null "http://127.0.0.1:${PORT}/" || exit 1

# tini становится PID 1 и пробрасывает сигналы приложению
ENTRYPOINT ["/sbin/tini", "--"]
# exec-форма (JSON-массив) + прямой вызов node.
# Не `npm start`: npm как посредник «проглатывает» сигналы остановки.
CMD ["node", "app.js"]
