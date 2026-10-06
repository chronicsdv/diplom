# Helm-чарт Craftista

Разворачивает всё приложение: frontend, catalogue, recommendation, voting и PostgreSQL.

Имена Service (`catalogue`, `recco`, `voting`, `catalogue-db`) зашиты в коде приложения,
поэтому имена ресурсов фиксированные: **один релиз на один namespace**.

## Установка
```bash
kubectl create namespace craftista
kubectl -n craftista create secret generic craftista-db \
  --from-literal=DB_NAME=catalogue \
  --from-literal=DB_USER=devops \
  --from-literal=DB_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"

helm upgrade --install craftista helm/craftista -n craftista
```

Другая версия образов (так будет делать CD):
```bash
helm upgrade --install craftista helm/craftista -n craftista --set global.imageTag=sha-abc1234
```

## Проверка без установки
```bash
helm lint helm/craftista --strict
helm template craftista helm/craftista -n craftista
```

## Основные настройки (`values.yaml`)
| Параметр | Что задаёт |
|---|---|
| `global.imageTag` | тег образов всех сервисов |
| `<сервис>.image.repository / tag` | образ конкретного сервиса (tag пуст = global) |
| `<сервис>.replicaCount`, `<сервис>.resources` | реплики и ресурсы |
| `database.existingSecret` | секрет с DB_NAME/DB_USER/DB_PASSWORD |
| `database.persistence.*`, `voting.persistence.*` | размер и StorageClass томов |
| `ingress.*` | включение, класс, host, TLS |
