# Craftista: DevOps-инфраструктура 

Дипломный проект. Приложение [Craftista](https://github.com/chronicsdv/diplom/tree/main/craftista) (четыре микросервиса) развёрнуто в Kubernetes-кластере, который целиком создаётся автоматически: виртуальные машины, Kubernetes, GitOps-доставка, мониторинг, логирование и оповещения.

## Что реализовано

| Задача | Решение |
|---|---|
| Инфраструктура как код | Vagrant (ВМ в Hyper-V), Ansible + Kubespray (Kubernetes), Helm и Kustomize (стек) |
| Запуск «с нуля одной командой» | `./up.sh` или workflow `infra` в GitHub Actions |
| CI | GitHub Actions: линтеры, тесты, сборка образов (артефакты), интеграционный тест, публикация в GHCR |
| CD (GitOps) | CI прописывает тег образа в git, Argo CD синхронизирует кластер |
| Мониторинг | kube-prometheus-stack: Prometheus, Grafana, Alertmanager |
| Логирование | ELK на ECK: Filebeat, Logstash, Elasticsearch, Kibana |
| Оповещения | Telegram: алерты Alertmanager, результат CI, результат деплоя Argo CD |

## Архитектура

```mermaid
flowchart LR
    dev["Разработчик"] -->|push| gh["GitHub: репозиторий"]
    gh --> ci["GitHub Actions: CI"]
    ci -->|образы| ghcr["GHCR"]
    ci -->|"тег образа в helm/craftista/values.yaml"| gh
    gh -->|"следит за git"| argo["Argo CD"]
    ghcr -->|"pull образов"| k8s

    subgraph win["Windows-хост: Hyper-V (Vagrant)"]
        subgraph k8s["Kubernetes (Kubespray)"]
            cp["craftista-cp: control plane + etcd"]
            w1["craftista-w1"]
            w2["craftista-w2"]
            w3["craftista-w3"]
        end
    end

    argo -->|деплой| app["Приложение: frontend, catalogue, recommendation, voting"]
    app --- k8s
    prom["Prometheus + Grafana + Alertmanager"] --- k8s
    elk["Filebeat -> Logstash -> Elasticsearch -> Kibana"] --- k8s
    prom -->|алерты| tg["Telegram"]
    argo -->|результат деплоя| tg
    ci -->|результат CI| tg
```

### Кластер

| Узел | Роль | Память | IP (резерв в роутере) |
|---|---|---|---|
| craftista-cp | control plane, etcd | 5 ГБ | 192.168.0.105 |
| craftista-w1 | worker | 4 ГБ | 192.168.0.103 |
| craftista-w2 | worker | 5 ГБ | 192.168.0.104 |
| craftista-w3 | worker | 5 ГБ | 192.168.0.102 |

- ОС: Ubuntu Server 24.04 (box `gusztavvargadr/ubuntu-server-2404-lts`), гипервизор Hyper-V.
- Kubernetes ставит Kubespray `v2.32.0` (версия зафиксирована в `up.sh`), сеть Calico, хранилище `local-path`.
- На Hyper-V Vagrant не умеет статические IP, поэтому у каждой ВМ фиксированный MAC, под который в роутере зарезервирован адрес.

### Стек

| Компонент | Версия | Как ставится |
|---|---|---|
| Traefik (Ingress) | чарт 41.7.1 | Helm |
| Argo CD | чарт 10.10.3 | Helm |
| kube-prometheus-stack | чарт 92.7.0 | Helm |
| ECK-оператор | 3.5.0 | Helm, чарт лежит в репозитории (`bootstrap/charts`) |
| Elasticsearch, Logstash, Kibana, Filebeat | 8.19.0 | Kustomize (`bootstrap/elk`), ресурсы ECK |
| Приложение Craftista | тег `sha-<коммит>` | Helm-чарт `helm/craftista`, ставит Argo CD |

## Структура репозитория

```
up.sh                    запуск всего с нуля
up-yandex.sh, start-yandex.sh   прежний вариант для Yandex Cloud (архивный)
vagrant/Vagrantfile      описание ВМ (рабочая копия лежит в Windows-папке, см. ниже)
ansible/                 подготовка узлов и установка Kubernetes
  bootstrap-kubespray.sh   ставит Ansible в venv и клонирует Kubespray
  prepare.yml              подготовка узлов (в том числе vm.max_map_count для Elasticsearch)
  inventory/hosts.ini      статический inventory (IP узлов)
  inventory/group_vars/k8s_cluster/overrides.yml   настройки Kubespray (Calico, порт метрик etcd)
  inventory/group_vars/k8s_cluster/addons.yml      аддоны Kubespray: Helm, metrics-server, local-path-provisioner
bootstrap/               установка стека на готовый кластер
  install-stack.sh         Traefik, Argo CD, приложение, мониторинг, ELK
  *-values.yaml            значения Helm-чартов
  elk/                     манифесты Elasticsearch, Logstash, Kibana, Filebeat, Ingress Kibana
  charts/                  ECK-оператор (чарт в репозитории)
argocd/application.yaml  Argo CD Application: следит за helm/craftista
helm/craftista/          Helm-чарт приложения (основной способ деплоя)
k8s/                     те же сервисы обычными манифестами для kubectl apply -k k8s/ (запасной способ без Helm)
craftista/               исходники сервисов, docker-compose.yml, smoke-test.sh
terraform/               Terraform для Yandex Cloud (альтернативный вариант)
.github/workflows/       ci.yml (CI и CD), infra.yml (создание кластера)
```

## Требования

Один раз на Windows-хосте:

1. Windows с включённым Hyper-V и WSL2 (Ubuntu).
2. Vagrant для Windows (`winget install Hashicorp.Vagrant`) и добавленный box:
   `vagrant box add --name gusztavvargadr/ubuntu-server-2404-lts <файл>.box`
   (box можно хранить локально и не скачивать из интернета при каждом запуске).
3. Внешний коммутатор Hyper-V (PowerShell от администратора, имя адаптера свое):
   `New-VMSwitch -Name "k8s-external" -NetAdapterName "Ethernet" -AllowManagementOS $true`
4. В роутере зарезервированы адреса под MAC-адреса ВМ (таблица ниже).
5. Папка с Vagrantfile на диске Windows (не в `\\wsl$`), например `D:\vagrant-ubuntu`.
   Скопируйте туда `vagrant/Vagrantfile` и положите рядом открытый ключ `craftista.pub`.
   Путь к папке задаётся переменной `VAGRANT_WIN_DIR` (по умолчанию `D:\vagrant-ubuntu`).

| ВМ | MAC | IP |
|---|---|---|
| craftista-cp | 00:15:5D:0A:01:01 | 192.168.0.105 |
| craftista-w1 | 00:15:5D:0A:02:01 | 192.168.0.103 |
| craftista-w2 | 00:15:5D:0A:02:02 | 192.168.0.104 |
| craftista-w3 | 00:15:5D:0A:02:03 | 192.168.0.102 |

В WSL (Ubuntu): ключ `~/.ssh/craftista` (пользователь на ВМ `vagrant`), пакеты `git`, `python3`, `kubectl`, `helm`, `openssl`, `gettext-base` (для `envsubst`).

## Запуск с нуля

### Подготовка секретов

Файл `.secrets.env` в корне репозитория (в git не попадает):

```
TELEGRAM_BOT_TOKEN=<токен бота>
TELEGRAM_CHAT_ID=<id чата или группы>
```

Токен и chat_id нужны для алертов, уведомлений Argo CD и результата CI. Те же значения должны быть в GitHub Secrets (`TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHAT_ID`). Для Argo CD нужен чат-группа: личный чат Argo CD не принимает.

### Вариант 1: из консоли

Откройте Ubuntu **от имени администратора** (Hyper-V требует прав, из терминала VS Code не сработает):

```bash
cd ~/diplom2
./up.sh
```

Полный цикл занимает 30-40 минут:

1. `vagrant up` на Windows создаёт 4 ВМ (через `powershell.exe`).
2. Ansible ждёт SSH на всех узлах и выполняет `prepare.yml`.
3. Kubespray ставит Kubernetes (до 3 попыток при сбое загрузки).
4. Обновляется `~/.kube/config`.
5. `bootstrap/install-stack.sh` ставит Traefik, Argo CD, приложение, мониторинг и ELK.

Скрипт идемпотентный: при ошибке его можно запустить повторно.

Полезные режимы:

```bash
./up.sh kubeconfig              # только обновить kubeconfig
./up.sh stack                   # только стек
ONLY="monitoring elk" ./up.sh stack   # отдельные компоненты: traefik argocd app monitoring elk
SKIP_VMS=1 ./up.sh              # ВМ уже запущены
```

### Вариант 2: из GitHub Actions

На компьютере с WSL запущен self-hosted раннер (Ubuntu от администратора):

```bash
cd ~/actions-runner && ./run.sh
```

Workflow `infra` (`.github/workflows/infra.yml`):

- запускается при пуше в `main`, если менялись `ansible/`, `bootstrap/`, `vagrant/`, `argocd/application.yaml` или `up.sh`, и вручную (Actions, infra, Run workflow);
- проверяет `kubectl get nodes`: **если кластера нет, запускает `./up.sh`**, если есть, применяет только изменившиеся компоненты стека (при ручном запуске весь стек).

Раннер включают только когда он нужен. CI и CD работают на облачных раннерах GitHub и от него не зависят.

## CI/CD

Файл `.github/workflows/ci.yml`, запускается на коммит в любую ветку:

```mermaid
flowchart LR
    lint["Линтеры Dockerfile"] --> build
    t1["catalogue: flake8, pytest"] --> build
    t2["frontend: ESLint, mocha"] --> build
    t3["recommendation: gofmt, vet, test"] --> build
    t4["voting: mvn verify"] --> build
    build["Сборка образов (артефакты)"] --> int["Интеграционный тест: compose + smoke-test"]
    int --> push["Публикация образов в GHCR"]
    push --> deploy["Тег образа в git (только main)"]
    deploy --> argo["Argo CD синхронизирует кластер"]
    helm["Helm lint + kubeconform"] --> notify
    tf["Terraform fmt + validate"] --> notify
    deploy --> notify["Уведомление в Telegram"]
```

1. **Проверки:** линтеры Dockerfile (hadolint), юнит-тесты и линтеры каждого сервиса, `helm lint` и `kubeconform`, `terraform validate`.
2. **Сборка:** каждый образ собирается один раз и сохраняется как артефакт запуска (`image-<сервис>`), jar сервиса voting сохраняется как `voting-jar`.
3. **Интеграционный тест:** образы берутся из артефактов, поднимаются все сервисы через `docker compose`, `craftista/smoke-test.sh` проверяет цепочку frontend, catalogue, recommendation, voting и голосование. Отчёт теста сохраняется как артефакт `integration-report`.
4. **Публикация:** только после успешного теста те же образы из артефактов уходят в GHCR (`ghcr.io/<владелец>/craftista-<сервис>`) с тегами `sha-<коммит>`, именем ветки и `latest` для основной ветки.
5. **CD (GitOps, только `main`):** задача `deploy` прописывает новый тег в `helm/craftista/values.yaml` и коммитит его от имени бота. Дальше работает Argo CD.
6. **Уведомление:** итог CI приходит в Telegram.

**Argo CD** (`argocd/application.yaml`) следит за `helm/craftista` в ветке `main` и автоматически синхронизирует кластер (`prune`, `selfHeal`). Результат деплоя приходит в Telegram отдельным сообщением: деплой завершён, синхронизация не прошла, приложение деградировало.

Коммит бота `cd: deploy sha-...` появляется в `main` после каждого успешного CI. Перед своим пушем выполняйте `git pull --rebase`.

## Доступ к сервисам

Снаружи кластера наружу публикуются приложение, Grafana и Kibana через Traefik (HTTP на порту 80 воркеров). Для имён Grafana и Kibana на Windows-хосте добавьте в `C:\Windows\System32\drivers\etc\hosts` (редактор от администратора):

```
192.168.0.103 grafana.craftista.local kibana.craftista.local
```

| Сервис | Адрес | Логин |
|---|---|---|
| Приложение Craftista | http://192.168.0.103/ | не требуется |
| Grafana | http://grafana.craftista.local | `admin` |
| Kibana | http://kibana.craftista.local | `elastic` |
| Argo CD | `kubectl -n argocd port-forward svc/argocd-server 8080:443`, затем https://localhost:8080 | `admin` |

Пароли:

```bash
# Grafana
kubectl -n monitoring get secret monitoring-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
# Kibana (elastic)
kubectl -n logging get secret logs-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'; echo
# Argo CD (admin)
kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d; echo
```

Доступ без Ingress (запасной вариант):

```bash
kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80
kubectl -n logging port-forward svc/kibana-kb-http 5601:5601
```

## Мониторинг и оповещения

- **kube-prometheus-stack**: Prometheus (хранение 3 дня, но не более 3 ГБ), Grafana со стандартными дашбордами, Alertmanager, node-exporter, kube-state-metrics.
- **Метрики control plane:** etcd (отдельный порт метрик 2381, настраивается переменной `etcd_metrics_port` в `overrides.yml`), kube-scheduler и kube-controller-manager. Цели видны в Prometheus: Status, Targets.
- **Оповещения:** Alertmanager отправляет алерты в Telegram. Токен бота хранится в секрете `alertmanager-telegram`, chat_id подставляется при установке через `envsubst`.
- **Деплой:** Argo CD Notifications присылает результат выкатки в Telegram.

```bash
kubectl -n monitoring port-forward svc/monitoring-kube-prometheus-prometheus 9090:9090
```

## Логирование

Цепочка: **Filebeat** (DaemonSet на каждом узле) читает логи контейнеров, отправляет в **Logstash**, тот пишет в **Elasticsearch** индексы `logstash-ГГГГ.ММ.ДД`. Логи смотрят в **Kibana**.

- Хранение логов 3 дня (политика ILM `logs-3d`), реплик нет (один узел Elasticsearch).
- Логи самого пространства `logging` Filebeat не собирает, чтобы не создавать петлю.
- При первом входе в Kibana создайте Data view с шаблоном `logstash-*` (Discover).
- Elasticsearch требует `vm.max_map_count=262144`: параметр выставляет `ansible/prepare.yml`.

## Секреты

| Что | Где хранится |
|---|---|
| Токен Telegram и chat_id | `.secrets.env` (локально, вне git), GitHub Secrets для CI и `infra` |
| Пароль БД приложения | секрет `craftista-db`, создаётся `install-stack.sh` случайным значением, если его нет |
| Токен Telegram для Alertmanager | секрет `alertmanager-telegram` |
| Токен Telegram для Argo CD | секрет `argocd-notifications-secret` |
| SSH-ключ к ВМ | `~/.ssh/craftista` (вне репозитория) |

В репозитории секретов нет.

## Проверка работоспособности

```bash
kubectl get nodes
kubectl get pods -A | grep -vE 'Running|Completed'     # должно быть пусто
kubectl -n argocd get application craftista             # Synced / Healthy
cd craftista && docker compose up -d --build && ./smoke-test.sh   # локальная проверка приложения
```

## Известные ограничения

- Доступ к Grafana, Kibana и приложению по HTTP без TLS, только из локальной сети. Для продакшена нужен TLS (cert-manager) и аутентификация на входе.
- Порт метрик etcd (2381) открыт на IP узла без TLS: для продакшена его закрывают фаерволом так, чтобы он был доступен только узлам кластера.
- Один control plane и один узел Elasticsearch: отказоустойчивости нет.
- Метрики kube-proxy не собираются (он слушает только localhost).
- Памяти на воркерах мало (около 80-87% при полной нагрузке), поэтому тяжёлые приложения добавлять не стоит.
- Тег образа CD коммитит в тот же репозиторий и ту же ветку, поэтому перед пушем нужен `git pull --rebase`. В продакшене манифесты и теги обычно выносят в отдельный GitOps-репозиторий.
- Компоненты стека (Traefik, мониторинг, ELK) ставятся скриптом, а не через Argo CD. Приложение деплоится через Argo CD.

## Альтернативный вариант: Yandex Cloud

Каталог `terraform/` и скрипты `up-yandex.sh` и `start-yandex.sh` описывают прежнюю реализацию: ВМ в Yandex Cloud создаёт Terraform, дальше те же Ansible и Kubespray. Вариант сохранён как запасной: облако показало нестабильную выдачу ресурсов при создании третьей ВМ, поэтому основным стал локальный Hyper-V.

Внимание: `terraform apply` сам перезаписывает `ansible/inventory/hosts.ini` и `ansible/inventory/group_vars/k8s_cluster/api-cert.yml` адресами облачных ВМ. После работы с Yandex вернуть inventory для Vagrant можно командой `git checkout ansible/inventory/hosts.ini`.
