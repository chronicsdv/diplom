# ELK в кластере (ECK): Filebeat → Logstash → Elasticsearch → Kibana

Namespace `logging`. Версия стека одна на все компоненты (`version: 8.19.0` в каждом манифесте).

## Требования
- Установлен ECK-оператор (чарт лежит в `bootstrap/charts/eck-operator-3.5.0.tgz`):
  `helm upgrade --install elastic-operator bootstrap/charts/eck-operator-3.5.0.tgz -n elastic-system --create-namespace`
- На всех нодах `vm.max_map_count=262144` (в `ansible/prepare.yml` или командой ansible из README корня).
- Воркеры от 5 ГБ памяти: лимиты ELK около 5 ГБ (ES 2 ГБ, Kibana 1,5 ГБ, Logstash 1,25 ГБ, Filebeat 256 МБ на ноду).

## Установка
```
kubectl apply -k bootstrap/elk
kubectl -n logging get elasticsearch,logstash,kibana,beat,pods
```
Первый запуск несколько минут: тянутся образы (~3,5 ГБ суммарно). Состояние Elasticsearch `yellow` на одном узле нормально
(индексы создаются с одной репликой).

## Доступ к Kibana
```
kubectl -n logging port-forward svc/kibana-kb-http 5601:5601
kubectl -n logging get secret logs-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'; echo
```
Открыть http://localhost:5601, логин `elastic`. В Kibana создать data view `logstash-*` (Stack Management → Data Views),
затем Discover. Фильтр по приложению: `kubernetes.namespace: craftista`.

## Заметки
- Образы идут с docker.elastic.co, доступ с российских адресов нестабилен (403). При `ErrImagePull` повторить позже
  или зеркалировать образы в GHCR и указать их в поле `image` ресурсов.
- Индексы создаются по дням (`logstash-YYYY.MM.dd`) и сами не удаляются: диск Elasticsearch 8 ГБ, следить за заполнением.
