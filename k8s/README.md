# Kubernetes-манифесты Craftista

Применяются через Kustomize (встроен в kubectl): `kubectl apply -k k8s/`.

| Файл | Что внутри |
|---|---|
| `namespace.yaml` | namespace `craftista` |
| `postgres/` | StatefulSet + headless Service `catalogue-db` + `init.sql` (стартовые данные каталога) |
| `catalogue.yaml` | Deployment (2 реплики) + Service `catalogue:5000` |
| `recommendation.yaml` | Deployment (2 реплики) + Service **`recco`**:8080 (имя зашито во frontend) |
| `voting.yaml` | Deployment (1 реплика) + PVC `voting-data` + Service `voting:8080` |
| `frontend.yaml` | Deployment (2 реплики) + Service `frontend:3000` |
| `ingress.yaml` | Ingress для Traefik, весь трафик `/` во frontend |
| `secret.example.yaml` | пример секрета с паролем БД (не применяется, в git реальный пароль не кладём) |

`postgres/init.sql` это копия `craftista/catalogue/db/init.sql`: Kustomize не читает файлы вне своей папки.
Если меняете исходник, обновите копию.

## Первый деплой (вручную)

### 1. Образы в ghcr.io
```bash
cd ~/diplom2
read -rs GHCR_TOKEN        # вставьте personal access token (ввод не отображается), Enter
echo "$GHCR_TOKEN" | docker login ghcr.io -u chronicsdv --password-stdin

for s in catalogue frontend recommendation voting; do
  docker build -t ghcr.io/chronicsdv/craftista-$s:v0.1.0 \
    --label org.opencontainers.image.source=https://github.com/chronicsdv/diplom \
    craftista/$s
  docker push ghcr.io/chronicsdv/craftista-$s:v0.1.0
done
```
Метка `image.source` привязывает пакет к репозиторию `diplom`, чтобы потом GitHub Actions
мог пушить образы встроенным токеном.

### 2. Сделать пакеты публичными
GitHub → ваш профиль → Packages → каждый из 4 пакетов → Package settings → Change visibility → **Public**.
Иначе ноды не смогут скачать образы (`ImagePullBackOff`).

### 3. Namespace, секрет, приложение
```bash
kubectl apply -f k8s/namespace.yaml
kubectl -n craftista create secret generic craftista-db \
  --from-literal=DB_NAME=catalogue \
  --from-literal=DB_USER=devops \
  --from-literal=DB_PASSWORD="$(openssl rand -base64 24 | tr -dc 'A-Za-z0-9')"
kubectl apply -k k8s/
kubectl -n craftista get pods -w
```

### 4. Проверка
```bash
cd terraform && terraform output worker_ips && cd ..
BASE_URL=http://<IP_ЛЮБОГО_ВОРКЕРА> ./craftista/smoke-test.sh
```
Или откройте `http://<IP воркера>/` в браузере.

## Если что-то не так
```bash
kubectl -n craftista get pods,svc,ingress,pvc
kubectl -n craftista describe pod <имя>
kubectl -n craftista logs <имя>
kubectl get ingressclass          # должен быть класс traefik
```
