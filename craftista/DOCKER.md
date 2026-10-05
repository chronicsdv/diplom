# Craftista в Docker

## Запуск
```bash
cp .env.example .env             # один раз: задайте DB_PASSWORD в .env
docker compose up --build        # собрать и запустить (первый раз 3–6 минут)
```
Открыть: **http://localhost:3000**. Проверка всей цепочки: `./smoke-test.sh`

| Команда | Что делает |
|---|---|
| `docker compose up -d --build` | то же, в фоне |
| `docker compose ps` | статусы, у всех должно быть `healthy` |
| `docker compose logs -f voting` | логи сервиса |
| `docker compose down` | остановить, **данные сохраняются** |
| `docker compose down -v` | остановить и **стереть данные** (БД и голоса) |

## Структура
```
craftista/
├── docker-compose.yml          всё вместе, включая БД
├── .env.example                шаблон настроек БД (копия .env в git не кладётся)
├── docker-compose.debug.yml    необязательный: открывает порты бэкендов на 127.0.0.1
├── smoke-test.sh
├── frontend/        Dockerfile  .dockerignore
├── catalogue/       Dockerfile  .dockerignore  db/init.sql
├── voting/          Dockerfile  .dockerignore
└── recommendation/  Dockerfile  .dockerignore
```

## Где хранятся данные
| Данные | Где | Как |
|---|---|---|
| Товары каталога | контейнер `catalogue-db` (PostgreSQL), том `catalogue-db-data` | таблица создаётся и заполняется из `catalogue/db/init.sql` при первом запуске |
| Голоса | файл H2 `/data/votes` в контейнере `voting`, том `voting-data` | путь задаётся переменной `SPRING_DATASOURCE_URL` в compose |

Сервисы и порты: наружу открыт только frontend (3000). Остальные видны лишь внутри сети Docker:
catalogue:5000, recco:8080 (alias recommendation), voting:8080, catalogue-db:5432.
Заглянуть в бэкенд из браузера: `docker compose -f docker-compose.yml -f docker-compose.debug.yml up`.

## Проверка, что данные действительно сохраняются
1. Откройте http://localhost:3000, проголосуйте за любое оригами.
2. `docker compose restart voting catalogue-db` (или `down`, затем `up`) — голоса и товары на месте.
3. `docker compose down -v` — всё стёрто, следующий запуск начнётся с чистого листа.

## Особенности приложения
- Имена хостов зашиты в код (`catalogue`, `recco`, `voting`) — поэтому alias `recco` в compose.
- Параметры БД каталога задаются в `.env` (`DB_NAME`, `DB_USER`, `DB_PASSWORD`). В `catalogue/app.py`
  добавлено чтение переменных окружения поверх `config.json` (`DATA_SOURCE`, `DB_HOST`, `DB_NAME`,
  `DB_USER`, `DB_PASSWORD`). Пароль не хранится в файлах репозитория.
- Postgres создаёт пользователя и пароль только при первом запуске на пустом томе. Если позже
  поменяли `DB_PASSWORD` — выполните `docker compose down -v` (данные БД будут стёрты) или
  смените пароль внутри БД командой `ALTER USER`.
- Чтобы каталог работал на JSON без БД, уберите `DATA_SOURCE: db` и сервис `catalogue-db`.
- В frontend нет `package-lock.json`: выполните `cd frontend && npm install --package-lock-only`
  и закоммитьте файл — Dockerfile автоматически перейдёт на воспроизводимый `npm ci`.
- Если приложению не хватает записи на диск из-за `read_only: true`, уберите эту строку у сервиса.
