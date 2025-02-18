# HW 07. Настройка autovacuum с учетом особеностей производительности

### Подготовка
 - Создать инстанс ВМ с 2 ядрами и 4 Гб ОЗУ и SSD 10GB
 - Установить на него PostgreSQL 15 с дефолтными настройками

### Создать БД для тестов
 - выполнить подготовку базы
```commandline
pgbench -i postgres
```
```commandline
postgres=# \dt+
                          List of relations
 Schema |       Name       | Type  |  Owner   |  Size   | Description 
--------+------------------+-------+----------+---------+-------------
 public | pgbench_accounts | table | postgres | 13 MB   | 
 public | pgbench_branches | table | postgres | 40 kB   | 
 public | pgbench_history  | table | postgres | 0 bytes | 
 public | pgbench_tellers  | table | postgres | 40 kB   | 
(4 rows)
```
 - Запустить 
```commandline
pgbench -c8 -P 6 -T 60 -U postgres postgres
```
```commandline
postgres@postgres-02:~$ pgbench -c8 -P 6 -T 60 -U postgres postgres
pgbench (15.10 (Ubuntu 15.10-1.pgdg20.04+1))
starting vacuum...end.
progress: 6.0 s, 1473.2 tps, lat 5.414 ms stddev 4.089, 0 failed
progress: 12.0 s, 1487.5 tps, lat 5.378 ms stddev 3.616, 0 failed
progress: 18.0 s, 1481.2 tps, lat 5.400 ms stddev 3.630, 0 failed
progress: 24.0 s, 1486.0 tps, lat 5.383 ms stddev 3.828, 0 failed
progress: 30.0 s, 1504.3 tps, lat 5.317 ms stddev 3.613, 0 failed
progress: 36.0 s, 1505.3 tps, lat 5.313 ms stddev 3.504, 0 failed
progress: 42.0 s, 1505.3 tps, lat 5.315 ms stddev 3.342, 0 failed
progress: 48.0 s, 1484.8 tps, lat 5.383 ms stddev 3.842, 0 failed
progress: 54.0 s, 1439.3 tps, lat 5.560 ms stddev 3.354, 0 failed
progress: 60.0 s, 1512.3 tps, lat 5.289 ms stddev 3.410, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 89284
number of failed transactions: 0 (0.000%)
latency average = 5.375 ms
latency stddev = 3.630 ms
initial connection time = 12.376 ms
tps = 1488.183861 (without initial connection time)

```
### Применить параметры настройки PostgreSQL из прикрепленного к материалам занятия файла
Настройки:
```sql
SHOW config_file;
```
```commandline
               config_file               
-----------------------------------------
 /etc/postgresql/15/main/postgresql.conf
(1 row)
```
Вносим изменения
```commandline
postgres@postgres-02:~$ cat /etc/postgresql/15/main/postgresql.conf | tail -26
#------------------------------------------------------------------------------
# CUSTOMIZED OPTIONS
#------------------------------------------------------------------------------

# Add settings for extensions here

# DB Version: 11
# OS Type: linux
# DB Type: dw
# Total Memory (RAM): 4 GB
# CPUs num: 1
# Data Storage: hdd

max_connections = 40
shared_buffers = 1GB
effective_cache_size = 3GB
maintenance_work_mem = 512MB
checkpoint_completion_target = 0.9
wal_buffers = 16MB
default_statistics_target = 500
random_page_cost = 4
effective_io_concurrency = 2
work_mem = 6553kB
min_wal_size = 4GB
max_wal_size = 16GB
```
Перезагружаем кластер:
```bash
postgres@postgres-02:~$ pg_ctlcluster 15 main status
pg_ctl: server is running (PID: 2957)
/usr/lib/postgresql/15/bin/postgres "-D" "/var/lib/postgresql/15/main" "-c" "config_file=/etc/postgresql/15/main/postgresql.conf"

postgres@postgres-02:~$ pg_ctlcluster 15 main stop
Warning: stopping the cluster using pg_ctlcluster will mark the systemd unit as failed. Consider using systemctl:
  sudo systemctl stop postgresql@15-main

postgres@postgres-02:~$ pg_ctlcluster 15 main start
Warning: the cluster will not be running as a systemd service. Consider using systemctl:
  sudo systemctl start postgresql@15-main

postgres@postgres-02:~$ pg_ctlcluster 15 main status
pg_ctl: server is running (PID: 184960)
/usr/lib/postgresql/15/bin/postgres "-D" "/var/lib/postgresql/15/main" "-c" "config_file=/etc/postgresql/15/main/postgresql.conf"
```

### Протестировать заново
```commandline
pgbench -c8 -P 6 -T 60 -U postgres postgres
```
```commandline
postgres@postgres-02:~$ pgbench -c8 -P 6 -T 60 -U postgres postgres
pgbench (15.10 (Ubuntu 15.10-1.pgdg20.04+1))
starting vacuum...end.
progress: 6.0 s, 1487.3 tps, lat 5.363 ms stddev 3.906, 0 failed
progress: 12.0 s, 1522.0 tps, lat 5.255 ms stddev 3.702, 0 failed
progress: 18.0 s, 1507.8 tps, lat 5.302 ms stddev 3.823, 0 failed
progress: 24.0 s, 1478.5 tps, lat 5.408 ms stddev 3.895, 0 failed
progress: 30.0 s, 1494.3 tps, lat 5.350 ms stddev 3.830, 0 failed
progress: 36.0 s, 1493.5 tps, lat 5.354 ms stddev 3.810, 0 failed
progress: 42.0 s, 1505.3 tps, lat 5.312 ms stddev 3.745, 0 failed
progress: 48.0 s, 1486.5 tps, lat 5.379 ms stddev 3.506, 0 failed
progress: 54.0 s, 1512.0 tps, lat 5.290 ms stddev 3.561, 0 failed
progress: 60.0 s, 1494.5 tps, lat 5.350 ms stddev 3.632, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 60 s
number of transactions actually processed: 89899
number of failed transactions: 0 (0.000%)
latency average = 5.337 ms
latency stddev = 3.744 ms
initial connection time = 10.838 ms
tps = 1498.327405 (without initial connection time)
```

### Что изменилось и почему?
Было 
```commandline
number of transactions actually processed: 89284
number of failed transactions: 0 (0.000%)
latency average = 5.375 ms
latency stddev = 3.630 ms
initial connection time = 12.376 ms
tps = 1488.183861 (without initial connection time)
```
Стало
```commandline
number of transactions actually processed: 89899
number of failed transactions: 0 (0.000%)
latency average = 5.337 ms
latency stddev = 3.744 ms
initial connection time = 10.838 ms
tps = 1498.327405 (without initial connection time)
```
Изменения незначительны. Причина - используется nvme диск. 

### Создать таблицу с текстовым полем и заполнить случайными или сгенерированными данным в размере 1млн строк

Создаем таблицу
```sql
CREATE TABLE test (
    field_1 TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```
```bash
postgres=# \dt+
                      List of relations
 Schema | Name | Type  |  Owner   |    Size    | Description 
--------+------+-------+----------+------------+-------------
 public | test | table | postgres | 8192 bytes | 
(1 row)
```
Заполняем данными
```sql
INSERT INTO
  test (field_1)
SELECT
  md5(random()::text)
FROM
  generate_series(1,1000000);
```

Проверяем
```commandline
postgres=# SELECT COUNT (*) FROM test ;
  count  
---------
 1000000
(1 row)
```

### Посмотреть размер файла с таблицей
Размер таблицы v1:
```sql
\dt+
```
```commandline
                   List of relations
 Schema | Name | Type  |  Owner   | Size  | Description 
--------+------+-------+----------+-------+-------------
 public | test | table | postgres | 73 MB | 
(1 row)
```
Размер таблицы v2:
```sql
SELECT pg_size_pretty( pg_total_relation_size( 'test' ) );
```
```commandline
 pg_size_pretty 
----------------
 73 MB
(1 row)
```

Путь до директории с базами = Data directory + 'base'
```bash
postgres@postgres-02:~$ pg_lsclusters 
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
```
Базы лежат в `/var/lib/postgresql/15/main`, в качестве имен используются `oid`
```sql
SELECT oid,datname from pg_database WHERE datname = 'postgres';
```
```commandline
 oid | datname  
-----+----------
   5 | postgres
(1 row)
```

Таблицы идентифицируются так же:
```sql
SELECT 'public.test'::regclass::oid;
```
```commandline
  oid  
-------
 16440
(1 row)
```
Таким образом, путь до файла с таблицей будет `/var/lib/postgresql/15/main/base/5/16440`
```commandline
postgres@postgres-02:~$ ls -pla /var/lib/postgresql/15/main/base/5/16440
-rw------- 1 postgres postgres 76562432 Jan 25 13:40 /var/lib/postgresql/15/main/base/5/16440

postgres@postgres-02:~$ du -ms /var/lib/postgresql/15/main/base/5/16440
74	/var/lib/postgresql/15/main/base/5/16440
```

Но лучше пользоваться вот этим, т.к. имя файла не всегда соответствует `oid` (например после `VACUUM FULL`):
```sql
select t.relname, t.oid, current_setting('data_directory')||'/'||pg_relation_filepath(t.oid)
from pg_class t
  join pg_namespace ns on ns.oid = t.relnamespace
where relkind = 'r'
and ns.nspname = 'public';
```
```commandline
 relname |  oid  |                 ?column?                 
---------+-------+------------------------------------------
 test    | 16440 | /var/lib/postgresql/15/main/base/5/16451
(1 row)
```

### 5 раз обновить все строчки и добавить к каждой строчке любой символ
```sql
DO $$
  BEGIN
    FOR i IN 0..5 LOOP
      UPDATE test SET field_1 = field_1||'_';
    END LOOP;
  END;
$$;
```

### Посмотреть количество мертвых строчек в таблице и когда последний раз приходил автовакуум
 - Подождать некоторое время, проверяя, пришел ли автовакуум
```sql
SELECT relname, 
       n_live_tup, 
       n_dead_tup, 
       trunc(100*n_dead_tup/(n_live_tup+1))::float "ratio%", 
       last_autovacuum 
FROM pg_stat_user_tables 
WHERE relname = 'test';
``` 
```commandline
 relname | n_live_tup | n_dead_tup | ratio% |        last_autovacuum        
---------+------------+------------+--------+-------------------------------
 test    |    1000000 |    6000000 |    599 | 2025-01-25 14:35:11.330086+00
(1 row)
```
Спустя некоторое время (60+ секунд по умолчанию):
```commandline
 relname | n_live_tup | n_dead_tup | ratio% |        last_autovacuum        
---------+------------+------------+--------+-------------------------------
 test    |    1000000 |          0 |      0 | 2025-01-25 14:42:13.280024+00
(1 row)
```

### 5 раз обновить все строчки и добавить к каждой строчке любой символ
```sql
DO $$
  BEGIN
    FOR i IN 0..5 LOOP
      UPDATE test SET field_1 = field_1||'_';
    END LOOP;
  END;
$$;
```

### Посмотреть размер файла с таблицей

```commandline
postgres@postgres-02:~$ ls -pla /var/lib/postgresql/15/main/base/5/16440
-rw------- 1 postgres postgres 535928832 Jan 25 14:41 /var/lib/postgresql/15/main/base/5/16440

postgres@postgres-02:~$ du -ms /var/lib/postgresql/15/main/base/5/16440
557	/var/lib/postgresql/15/main/base/5/16440
```

### Отключить Автовакуум на конкретной таблице
Отключаем (устанавливаем отличающуюся от дефолтной опцию на таблицу):
```sql
ALTER TABLE test SET (autovacuum_enabled = off);
```
Проверяем:
```sql
SELECT relname, reloptions FROM pg_class WHERE relname='test';
```
```commandline
 relname |        reloptions        
---------+--------------------------
 test    | {autovacuum_enabled=off}
(1 row)
```

### 10 раз обновить все строчки и добавить к каждой строчке любой символ
```sql
DO $$
  BEGIN
    FOR i IN 0..10 LOOP
      UPDATE test SET field_1 = field_1||'Ж';
    END LOOP;
  END;
$$;
```
```sql
SELECT * FROM test LIMIT 1;
```
```commandline
                         field_1                          |          updated_at           
----------------------------------------------------------+-------------------------------
 023ab076c5ea37ed9ef573d87625563d_____________ЖЖЖЖЖЖЖЖЖЖЖ | 2025-01-25 13:33:40.463303+00
(1 row)
```
Проверяем что автовакуум не трогал:
```sql
SELECT relname, 
       n_live_tup, 
       n_dead_tup, 
       trunc(100*n_dead_tup/(n_live_tup+1))::float "ratio%", 
       last_autovacuum 
FROM pg_stat_user_tables 
WHERE relname = 'test';
```
```commandline
 relname | n_live_tup | n_dead_tup | ratio% |        last_autovacuum        
---------+------------+------------+--------+-------------------------------
 test    |    1000000 |   10999931 |   1099 | 2025-01-25 14:46:13.564595+00
(1 row)
```

### Посмотреть размер файла с таблицей
```commandline
postgres@postgres-02:~$ ls -pla /var/lib/postgresql/15/main/base/5/16440
-rw------- 1 postgres postgres 1073741824 Jan 25 14:55 /var/lib/postgresql/15/main/base/5/16440

postgres@postgres-02:~$ du -ms /var/lib/postgresql/15/main/base/5/16440
1025	/var/lib/postgresql/15/main/base/5/16440
```

### Объясните полученный результат
Разбирали в лекции. Особенности реализации механизма MVCC - через служебные поля xmix и xmax связываются текущая реальность (aka "main" @ git) и все остальные версии реальности (aka любая ветка @ git).

Реализация подразумевает **НЕ** удаление данных (в файлах), а их накопление с соответствующими пометками (поле `xmax` не равно 0). Их очисткой (а еще сбором статистики) занимается vacuum.

Удаленные строки высвобождают страницы файла и переиспользуются для новых записей.

Для уменьшения размера файла требуется дефрагментация
```sql
VACUUM FULL;
```

[https://habr.com/ru/articles/501516/](https://habr.com/ru/articles/501516/)

 - Не забудьте включить автовакуум)

```sql
ALTER TABLE test SET (autovacuum_enabled = on);
```