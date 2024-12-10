# HW 02
## Запуск PostgreSQL в docker
Склонировать содержимое директории infra, поменять IP адрес на свой.
```
$ grep -Rne "192.168.1.254" .
```
```
./infra/docker-compose.yml:85:      DATA_SOURCE_URI: "192.168.1.254:5432/otusdb?sslmode=disable"
./infra/prometheus/prometheus.yml:19:        - "192.168.1.254:42007"
./infra/prometheus/prometheus.yml:24:        - "192.168.1.254:42008"
./infra/grafana/provisioning/datasources/prometheus.yml:5:  url: http://192.168.1.254:42007
```
Убедиться что выданы корректные права, см. комментарии в `docker-compose.yml`
```
$ cat infra/docker-compose.yml | grep -i ensure
      # ensure "chown -R 5050:0 ./pgadmin/"
      # ensure "chown -R 65534:65534 ./prometheus"
      # ensure "chown -R 472:0 ./grafana/data"
      # ensure "chown -R 472:0 ./grafana/provisioning"
      # ensure "chown -R 472:0 ./grafana/dashboard.yaml"
      # ensure "chown -R 472:0 ./grafana/dashboards"
```
В дополнение к PostgreSQL 15.10 разворачиваются:
 - [http://0.0.0.0:42009](http://0.0.0.0:42009) **PGAdmin4** `8.13.0` - для удобства управления БД через web-интерфейс
 - [http://0.0.0.0:42008](http://0.0.0.0:42008) **Postgres Exporter** `0.16.0` - для сбора метрик PostgreSQL, конфиг в `./postgres/exporter/queries.yaml`
 - [http://0.0.0.0:42007](http://0.0.0.0:42007) **Prometheus** `v3.0.1` - для хранения метрик, получаемых от Postgres Exporter
 - [http://0.0.0.0:42006](http://0.0.0.0:42006) **Grafana** `11.4.0` - для построения графиков метрик PostgreSQL

Логины и пароли указаны в `docker-ompose.yml` для каждого сервиса

## Выполнение заданий
### Подключится из контейнера с клиентом к контейнеру с сервером и сделать таблицу с парой строк
### Подключится к контейнеру с сервером с ноутбука/компьютера извне инстансов ЯО/места установки докера
### Удалить контейнер с сервером
### Создать его заново
### Подключится снова из контейнера с клиентом к контейнеру с сервером
### Проверить, что данные остались на месте
