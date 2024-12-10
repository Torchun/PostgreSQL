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

Запуск сервисов
```
docker-compose -f docker-compose.yml up -d
```
Проверяем что контейнеры работают
```
docker-compose -f docker-compose.yml ps -a
```
```
      Name                     Command                  State                            Ports                     
-------------------------------------------------------------------------------------------------------------------
grafana             /run.sh                          Up             0.0.0.0:42006->3000/tcp,:::42006->3000/tcp     
pgadmin             /entrypoint.sh                   Up             443/tcp, 0.0.0.0:42009->80/tcp,:::42009->80/tcp
postgres            docker-entrypoint.sh postg ...   Up (healthy)   0.0.0.0:5432->5432/tcp,:::5432->5432/tcp       
postgres-exporter   postgres_exporter                Up             0.0.0.0:42008->9187/tcp,:::42008->9187/tcp     
prometheus          /bin/prometheus --config.f ...   Up             0.0.0.0:42007->9090/tcp,:::42007->9090/tcp     
```

## Выполнение заданий
### Подключится из контейнера с клиентом к контейнеру с сервером и сделать таблицу с парой строк
Т.к. у нас уже есть docker image с postgresql, внутри которого есть psql клиент - переиспользуем его. 

Порождаем новый контейнер командой:
```
docker run --rm -ti postgres:15.10 psql -h 192.168.1.254 -p 5432 -U otus -d otusdb
```
где
 - `--rm` - уничтожение контейнера после завершения PID 1, т.е. после завершения работы внутри контейнера
 - `-ti` - интерактивная работа, сразу же попадаем в работу с указываемым далее шеллом\исполняемым файлом
 - `postgres:15.10` - docker image, который скачивается по умолчанию из dockerhub
 - `psql` - прописанный внутри контейнера в `$PATH` исполняемый файл клиента (поэтому указываем как название команды, без абсолютного пути)
 - `-h` - host, указываем "внейний" IP адрес, т.е. адрес хоста. 0.0.0.0 не подойдет т.к. docker daemon интерпретирует его как внутриконтейнерную сеть
 - `-p` порт, см `docker-compose.yml`
 - `-U` username, см. `docker-compose.yml`
 - `-d` database name, см. `docker-compose.yml`

Результат:
```
Password for user otus: 
psql (15.10 (Debian 15.10-1.pgdg120+1))
Type "help" for help.

otusdb=# \l
                                             List of databases
   Name    | Owner | Encoding |  Collate   |   Ctype    | ICU Locale | Locale Provider | Access privileges 
-----------+-------+----------+------------+------------+------------+-----------------+-------------------
 otusdb    | otus  | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 postgres  | otus  | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | 
 template0 | otus  | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/otus          +
           |       |          |            |            |            |                 | otus=CTc/otus
 template1 | otus  | UTF8     | en_US.utf8 | en_US.utf8 |            | libc            | =c/otus          +
           |       |          |            |            |            |                 | otus=CTc/otus
(4 rows)

otusdb=# \q
```
Создаем таблицу с парой строк:
```
otusdb=# create table persons(id serial, first_name text, second_name text);
CREATE TABLE

otusdb=# \dt+
                                  List of relations
 Schema |  Name   | Type  | Owner | Persistence | Access method | Size  | Description 
--------+---------+-------+-------+-------------+---------------+-------+-------------
 public | persons | table | otus  | permanent   | heap          | 16 kB | 
(1 row)


otusdb=# insert into persons(first_name, second_name) values('ivan', 'ivanov');
INSERT 0 1
otusdb=# insert into persons(first_name, second_name) values('petr', 'petrov');
INSERT 0 1

otusdb=# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
(2 rows)
```

### Подключится к контейнеру с сервером с ноутбука/компьютера извне инстансов ЯО/места установки докера
Т.к. был использован docker container с подключением через внешний (по отношению к контейнерам) IP - команды будут такими же.

### Удалить контейнер с сервером
```
$ docker-compose -f docker-compose.yml ps -a
      Name                     Command                  State                            Ports                     
-------------------------------------------------------------------------------------------------------------------
grafana             /run.sh                          Up             0.0.0.0:42006->3000/tcp,:::42006->3000/tcp     
pgadmin             /entrypoint.sh                   Up             443/tcp, 0.0.0.0:42009->80/tcp,:::42009->80/tcp
postgres            docker-entrypoint.sh postg ...   Up (healthy)   0.0.0.0:5432->5432/tcp,:::5432->5432/tcp       
postgres-exporter   postgres_exporter                Up             0.0.0.0:42008->9187/tcp,:::42008->9187/tcp     
prometheus          /bin/prometheus --config.f ...   Up             0.0.0.0:42007->9090/tcp,:::42007->9090/tcp     
```
Удаляем контейнер с PostgreSQL:
```
docker-compose -f docker-compose.yml down
```

Проверяем что контейнер удалён:
```
docker-compose -f docker-compose.yml ps -a
Name   Command   State   Ports
------------------------------
```

### Создать его заново
```
docker-compose -f docker-compose.yml up -d 
```
Проверяем:
```
docker-compose -f docker-compose.yml ps -a

      Name                     Command                  State                            Ports                     
-------------------------------------------------------------------------------------------------------------------
grafana             /run.sh                          Up             0.0.0.0:42006->3000/tcp,:::42006->3000/tcp     
pgadmin             /entrypoint.sh                   Up             443/tcp, 0.0.0.0:42009->80/tcp,:::42009->80/tcp
postgres            docker-entrypoint.sh postg ...   Up (healthy)   0.0.0.0:5432->5432/tcp,:::5432->5432/tcp       
postgres-exporter   postgres_exporter                Up             0.0.0.0:42008->9187/tcp,:::42008->9187/tcp     
prometheus          /bin/prometheus --config.f ...   Up             0.0.0.0:42007->9090/tcp,:::42007->9090/tcp     
```
Или можно проверить отдельно взятый контейнер:
```
docker ps -a | grep -i postgres
```
```
CONTAINER ID   IMAGE                              COMMAND                  CREATED              STATUS                        PORTS                                              NAMES
9623f5dbbaac   postgres:15.10                     "docker-entrypoint.s…"   24 seconds ago       Up 23 seconds (healthy)       0.0.0.0:5432->5432/tcp, :::5432->5432/tcp          postgres
```

### Подключится снова из контейнера с клиентом к контейнеру с сервером
```
docker run --rm -ti postgres:15.10 psql -h 192.168.1.254 -p 5432 -U otus -d otusdb
```

### Проверить, что данные остались на месте
```
otusdb=# \dt+
                                  List of relations
 Schema |  Name   | Type  | Owner | Persistence | Access method | Size  | Description 
--------+---------+-------+-------+-------------+---------------+-------+-------------
 public | persons | table | otus  | permanent   | heap          | 16 kB | 
(1 row)

otusdb=# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
(2 rows)
```
