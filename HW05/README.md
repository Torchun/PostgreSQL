# HW 05

## Задания

### Развернуть PostgreSQL
 - развернуть виртуальную машину любым удобным способом
 - поставить на неё PostgreSQL 15 любым способом

Принимаем что у нас OLTP нагрузка. Параметры "сервера":
 - 8 CPU
 - 16 GB RAM (генерация данных для тестов занимает много времени)
 - SSD (NVME) диск
Установка сделана в docker, см. [docker compose](docker-compose.yaml)


### Нагрузочное тестирование
 - настроить кластер PostgreSQL 15 на максимальную производительность не обращая внимание на возможные проблемы с надежностью в случае аварийной перезагрузки виртуальной машины
 - нагрузить кластер через утилиту через утилиту pgbench (https://postgrespro.ru/docs/postgrespro/14/pgbench)
 - написать какого значения tps удалось достичь, показать какие параметры в какие значения устанавливали и почему

Тестировать будем 5 разных конфигов:
 - `default` - без изменений, стандартный конфиг PostgreSQL 15.10
 - `pgconfig_org` - результат подсказки [pgconfig.org](https://www.pgconfig.org/#/?max_connections=100&pg_version=15&environment_name=OLTP&total_ram=32&cpus=8&drive_type=SSD&arch=x86-64&os_type=linux)
 - `pgconfigurator_cybertec_at` - результат подсказки [pgconfigurator.cybertec.at](https://pgconfigurator.cybertec.at/)
 - `pgtune_leopard_in_ua` - результат подсказки [pgtune.leopard.in.ua](https://pgtune.leopard.in.ua/?dbVersion=15&osType=linux&dbType=oltp&cpuNum=8&totalMemory=32&totalMemoryUnit=GB&connectionNum=100&hdType=ssd)
 - `custom` - попытка самостоятельно покрутить ручки с огладкой на статистики и мониторинг + чтение [tunables_explained](tunables_explained.md)

Конфиги подкладываем в docker-compose как `volume` дописывая в конец соответствующего файла вносимые изменения. Требуется рестарт контейнера:
```commandline
docker-compose -f docker-compose.yml down
# check & edit file *.conf
docker-compose -f docker-compose.yml up -d
```
```commandline
otusdb=# show config_file;
           config_file           
---------------------------------
 /etc/postgresql/postgresql.conf
(1 row)
```
### PGBENCH 

Создаем базу:
```commandline
otusdb=# CREATE DATABASE pgbench;
```

Наполняем тестовыми данными
```commandline
echo "Prepare DB"
echo " ~ 32 Gb of data, x2 times more than RAM"
docker run --rm -ti postgres:15.10 pgbench --username=otus -h 192.168.1.254 pgbench -i -s 2650
```
```
pgbench=# \dt+
                         List of relations
 Schema |       Name       | Type  | Owner |  Size   | Description 
--------+------------------+-------+-------+---------+-------------
 public | pgbench_accounts | table | otus  | 33 GB   | 
 public | pgbench_branches | table | otus  | 128 kB  | 
 public | pgbench_history  | table | otus  | 0 bytes | 
 public | pgbench_tellers  | table | otus  | 1184 kB | 
(4 rows)
```

Нагружаем:
```commandline
docker run --rm -ti postgres:15.10 pgbench --username=otus -h 192.168.1.254 pgbench -P 10 -j 4 -c 95 -N -T 300 >> log/pgbench.default.log 2>&1
```

### SYSBENCH

Собираем docker image [https://github.com/akopytov/sysbench/blob/master/Dockerfile](https://github.com/akopytov/sysbench/blob/master/Dockerfile)
```commandline
cd sysbench
docker build -t sysbench .
```

Проверяем что утилита доступна:
```
docker run --rm -ti --entrypoint=/bin/bash sysbench:latest
root@106d22203c9c:~# sysbench --version
sysbench 1.1.0-de18a03
```

Создаем базу:
```commandline
otusdb=# CREATE DATABASE sysbench;
```
Наполняем тестовыми данными (генерация идет очень долго)

[https://github.com/akopytov/sysbench?tab=readme-ov-file#general-syntax](https://github.com/akopytov/sysbench?tab=readme-ov-file#general-syntax)
```commandline
echo "Prepare DB"
echo " ~ 32 Gb of data, x2 times more than RAM"

sysbench \
  --db-driver=pgsql \
  --pgsql-host="192.168.1.254" \
  --pgsql-port=5432 \
  --pgsql-user=otus \
  --pgsql-password=password \
  --pgsql-db=sysbench \
  --table-size=10000000 \
  --tables=16 \
  --time=300 \
  --threads=4 \
  "/sysbench/src/lua/oltp_read_write.lua" \
  prepare
```
```
sysbench=# \dt+
                    List of relations
 Schema |  Name   | Type  | Owner |  Size   | Description 
--------+---------+-------+-------+---------+-------------
 public | sbtest1 | table | otus  | 1207 MB | 
 public | sbtest2 | table | otus  | 1376 MB | 
 public | sbtest3 | table | otus  | 1216 MB | 
 public | sbtest4 | table | otus  | 1197 MB | 
 public | sbtest5 | table | otus  | 1212 MB | 
 public | sbtest6 | table | otus  | 1380 MB | 
 public | sbtest7 | table | otus  | 1369 MB | 
 public | sbtest8 | table | otus  | 1204 MB | 
(8 rows)
```

Нагружаем:
```commandline
docker run --rm -ti --entrypoint=/bin/bash sysbench:latest
root@106d22203c9c:~# sysbench --version

sysbench \
  --db-driver=pgsql \
  --pgsql-host="192.168.1.254" \
  --pgsql-port=5432 \
  --pgsql-user=otus \
  --pgsql-password=password \
  --pgsql-db=sysbench \
  --time=300 \
  --threads=4 \
  "/sysbench/src/lua/oltp_read_write.lua" \
  run 
```

Для удаления данных
```commandline
sysbench \
  --db-driver=pgsql \
  --pgsql-host="192.168.1.254" \
  --pgsql-port=5432 \
  --pgsql-user=otus \
  --pgsql-password=password \
  --pgsql-db=sysbench \
  --time=300 \
  --threads=4 \
  "/sysbench/src/lua/oltp_read_write.lua" \
  cleanup
```

### Результаты

| config                     | pgbench TPS | sysbench TPS |
|----------------------------|-------------|--------------|
| default                    | 9476.953073 | 1035.4293    |
| pgconfig_org               | -           | -            |
| pgconfigurator_cybertec_at | -           | -            |
| pgtune_leopard_in_ua       | -           | -            |
| custom                     | -           | -            |


