# syntax=docker/dockerfile:1.7
# ^ Директива парсера: современный синтаксис (нужен для --mount=type=cache).

# =====================================================================
# CATALOGUE — Python + Flask (запуск через gunicorn), порт 5000
# 2 этапа: в builder ставим зависимости в виртуальное окружение,
# в runtime переносим только готовое окружение и код.
# =====================================================================

ARG PYTHON_VERSION=3.12

# ---------------------------------------------------------------------
# ЭТАП 1: builder — собираем виртуальное окружение (venv) с зависимостями
# ---------------------------------------------------------------------
# slim — урезанный debian: заметно меньше полного образа, но с glibc,
# поэтому готовые wheel-пакеты (например psycopg2-binary) ставятся без компилятора.
FROM python:${PYTHON_VERSION}-slim AS builder

# Не проверяем версию pip при каждом запуске (лишний сетевой запрос)
ENV PIP_DISABLE_PIP_VERSION_CHECK=1

# Создаём venv в /opt/venv — его целиком перенесём в итоговый образ
RUN python -m venv /opt/venv
# Ставим venv первым в PATH: команды python/pip теперь берутся оттуда
ENV PATH="/opt/venv/bin:$PATH"

WORKDIR /build
# Копируем только requirements.txt — слой с зависимостями кешируется,
# пока этот файл не изменился.
COPY requirements.txt ./
# Кеш pip живёт между сборками, но не раздувает образ.
# В requirements.txt уже есть: Flask, gunicorn, requests, flask_cors, psycopg2-binary.
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# ---------------------------------------------------------------------
# ЭТАП 2: runtime — итоговый образ
# ---------------------------------------------------------------------
FROM python:${PYTHON_VERSION}-slim AS runtime

LABEL org.opencontainers.image.title="craftista-catalogue" \
      org.opencontainers.image.description="Craftista product catalogue (Python/Flask)" \
      org.opencontainers.image.source="https://github.com/craftista/craftista" \
      org.opencontainers.image.licenses="Apache-2.0"

# PYTHONDONTWRITEBYTECODE — не создавать .pyc файлы (не нужны, лишние записи на диск)
# PYTHONUNBUFFERED       — логи сразу летят в stdout (без буферизации их видно в `docker logs`)
# PATH                   — используем venv, скопированный из builder
# GUNICORN_CMD_ARGS      — gunicorn сам читает эту переменную, поэтому параметры
#                          можно менять без пересборки (через `environment:` в compose):
#   --bind 0.0.0.0:5000   слушать на всех интерфейсах (иначе снаружи контейнера не достучаться)
#   --workers 2           2 процесса-воркера
#   --worker-tmp-dir      временные файлы heartbeat в RAM (/dev/shm) — рекомендация Docker/gunicorn
#   --access-logfile -    логи запросов в stdout
#   --error-logfile -     логи ошибок в stderr/stdout
#   --no-control-socket   отключить управляющий сокет gunicornc (появился в gunicorn 25.1):
#                         он по умолчанию пишет в ~/.gunicorn, а у нас корневая ФС read-only,
#                         из-за чего в логах была бы ошибка "Control server error: Read-only file system"
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PATH="/opt/venv/bin:$PATH" \
    GUNICORN_CMD_ARGS="--bind=0.0.0.0:5000 --workers=2 --worker-tmp-dir=/dev/shm --access-logfile=- --error-logfile=- --no-control-socket"

# Создаём системного пользователя без shell и домашней папки (uid 10001):
# приложение будет работать НЕ от root.
RUN groupadd --system --gid 10001 app \
 && useradd  --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

WORKDIR /app

# Переносим готовое окружение с зависимостями из builder
COPY --from=builder /opt/venv /opt/venv

# Код приложения — ОДНИМ COPY. Состав определяет белый список в .dockerignore:
#   app.py          — Flask-приложение
#   config.json     — версия, источник данных (json/db), параметры БД
#   products.json   — данные каталога (фаза 1, без БД)
#   templates/      — HTML-шаблон главной страницы
#   static/         — CSS и картинки
# Не попадают: app.py.bak, db.create.py, test_app.py, README, db/.
# app.py читает products.json и config.json из текущей папки (WORKDIR /app).
COPY --chown=app:app . .

# Дальше — никаких root-прав
USER app

EXPOSE 5000

# Проверка здоровья средствами Python (curl/wget в slim-образе нет).
# Запрашиваем /api/products: если ответ не 2xx или сервис не отвечает —
# urlopen бросает исключение, команда завершается с ошибкой → "unhealthy".
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
  CMD python -c "import urllib.request as u; u.urlopen('http://127.0.0.1:5000/api/products', timeout=2)"

# Продакшн-сервер gunicorn вместо встроенного сервера Flask (`flask run` не для продакшна).
# "app:app" = файл app.py : объект Flask с именем app. Параметры берутся из GUNICORN_CMD_ARGS.
# exec-форма → gunicorn становится PID 1 и сам корректно обрабатывает SIGTERM.
CMD ["gunicorn", "app:app"]
