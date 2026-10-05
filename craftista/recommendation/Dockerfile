# syntax=docker/dockerfile:1.7
# ^ Директива парсера: современный синтаксис (нужен для --mount=type=cache).

# =====================================================================
# RECOMMENDATION — Go + Gin, порт 8080
# 2 этапа: компиляция в golang-образе → крошечный итоговый образ
# со статическим бинарником (без Go-тулчейна и исходников).
# =====================================================================

# go.mod требует go 1.20; берём 1.22 — проверенная версия, совместимая с gin 1.9.1.
ARG GO_VERSION=1.22
ARG ALPINE_VERSION=3.22

# ---------------------------------------------------------------------
# ЭТАП 1: build — компилируем бинарник
# ---------------------------------------------------------------------
# --platform=$BUILDPLATFORM: компилятор всегда работает на архитектуре машины,
# где идёт сборка (быстро), а Go сам кросс-компилирует под целевую (amd64/arm64).
FROM --platform=$BUILDPLATFORM golang:${GO_VERSION}-alpine AS build
# Эти ARG BuildKit заполняет автоматически (целевая ОС/архитектура образа)
ARG TARGETOS
ARG TARGETARCH
WORKDIR /src

# Сначала только go.mod/go.sum и загрузка модулей — слой кешируется,
# пока список зависимостей не менялся. Кеш модулей живёт между сборками.
COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download

# Теперь весь исходный код одним COPY (состав задаёт белый список в .dockerignore:
# main.go, api/, data/, config.json, templates/, static/).
COPY . .

# Флаги сборки:
#   CGO_ENABLED=0     → полностью статический бинарь (не нужна libc → можно alpine/scratch)
#   -trimpath         → убрать локальные пути из бинарника (воспроизводимость, безопасность)
#   -ldflags="-s -w" → убрать таблицу символов и отладочную инфо (бинарь заметно меньше)
# Сразу после компиляции складываем в /rootfs ВСЁ, что нужно сервису в рантайме
# (он ищет config.json, templates/, static/ относительно рабочей папки!).
# Так в итоговом образе хватит одного COPY --from=build.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go build -trimpath -ldflags="-s -w" -o /rootfs/recommendation . \
 && cp -r config.json templates static /rootfs/

# ---------------------------------------------------------------------
# ЭТАП 2: runtime — минимальный образ
# ---------------------------------------------------------------------
FROM alpine:${ALPINE_VERSION} AS runtime

LABEL org.opencontainers.image.title="craftista-recommendation" \
      org.opencontainers.image.description="Craftista recommendation service (Go/Gin)" \
      org.opencontainers.image.source="https://github.com/craftista/craftista" \
      org.opencontainers.image.licenses="Apache-2.0"

# Непривилегированный пользователь (uid 10001), без домашней папки
RUN addgroup -S -g 10001 app && adduser -S -u 10001 -G app -H app

WORKDIR /app

# Одним COPY переносим готовое содержимое /rootfs:
#   recommendation  — скомпилированный бинарь
#   config.json     — main.go читает его при рендере главной страницы
#   templates/      — HTML-шаблоны (router.LoadHTMLGlob("templates/*"))
#   static/         — CSS и картинки (router.Static("/static", "./static"))
COPY --from=build --chown=app:app /rootfs ./

# GIN_MODE=release — отключает отладочный режим Gin (меньше шума в логах, выше скорость)
ENV GIN_MODE=release

USER app

# Порт 8080 зашит в main.go (router.Run(":8080"))
EXPOSE 8080

# Отдельного /health нет — используем готовый статус-эндпоинт сервиса.
# wget есть в busybox alpine.
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget -q -O /dev/null http://127.0.0.1:8080/api/recommendation-status || exit 1

# exec-форма → бинарь становится PID 1 и получает SIGTERM напрямую
ENTRYPOINT ["./recommendation"]
