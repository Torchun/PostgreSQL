# HW 08
 <hr>

### Настройте выполнение контрольной точки раз в 30 секунд.
```postgresql
SHOW checkpoint_timeout;
```
```commandline
 checkpoint_timeout 
--------------------
 5min
(1 row)
```
```commandline
echo "log_checkpoints = on" >> /etc/postgresql/15/main/postgresql.conf
echo "checkpoint_timeout = 30s" >> /etc/postgresql/15/main/postgresql.conf
cat /etc/postgresql/15/main/postgresql.conf | tail -6
```
```
#------------------------------------------------------------------------------
# CUSTOMIZED OPTIONS
#------------------------------------------------------------------------------

log_checkpoints = on
checkpoint_timeout = 30s
```
```commandline
pg_ctlcluster 15 main stop
pg_ctlcluster 15 main start
```
```postgresql
SHOW checkpoint_timeout;
```
```commandline
 checkpoint_timeout 
--------------------
 30s
(1 row)
```

### 10 минут c помощью утилиты pgbench подавайте нагрузку.

Подготовимся к сравнению (см. следующий пункт)
```postgresql
SELECT pg_stat_reset();
SELECT pg_stat_reset_shared('bgwriter');
SELECT * FROM pg_stat_bgwriter;
```
```commandline
$ du -ms /var/lib/postgresql/15/main/pg_wal
17	/var/lib/postgresql/15/main/pg_wal
```
Подаем нагрузку:
```commandline
pgbench -i postgres # 33 Mb
pgbench -c8 -P 60 -T 600 -U postgres postgres
```
```commandline
pgbench (15.10 (Ubuntu 15.10-1.pgdg20.04+1))
starting vacuum...end.
progress: 60.0 s, 1497.9 tps, lat 5.337 ms stddev 3.408, 0 failed
progress: 120.0 s, 1502.2 tps, lat 5.323 ms stddev 3.435, 0 failed
progress: 180.0 s, 1504.1 tps, lat 5.317 ms stddev 3.408, 0 failed
progress: 240.0 s, 1514.7 tps, lat 5.279 ms stddev 3.359, 0 failed
progress: 300.0 s, 1497.7 tps, lat 5.338 ms stddev 3.429, 0 failed
progress: 360.0 s, 1507.0 tps, lat 5.306 ms stddev 3.393, 0 failed
progress: 420.0 s, 1507.2 tps, lat 5.305 ms stddev 3.406, 0 failed
progress: 480.0 s, 1508.3 tps, lat 5.301 ms stddev 3.342, 0 failed
progress: 540.0 s, 1500.8 tps, lat 5.328 ms stddev 3.397, 0 failed
progress: 600.0 s, 1501.6 tps, lat 5.325 ms stddev 3.342, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 8
number of threads: 1
maximum number of tries: 1
duration: 600 s
number of transactions actually processed: 902495
number of failed transactions: 0 (0.000%)
latency average = 5.316 ms
latency stddev = 3.392 ms
initial connection time = 13.692 ms
tps = 1504.152507 (without initial connection time)
```

### Измерьте, какой объем журнальных файлов был сгенерирован за это время. 
```commandline
du -ms /var/lib/postgresql/15/main/pg_wal
97	/var/lib/postgresql/15/main/pg_wal
```

### Оцените, какой объем приходится в среднем на одну контрольную точку.
`(97 - 17) / (600 / 30)` = `4Mb`

### Проверьте данные статистики: все ли контрольные точки выполнялись точно по расписанию. Почему так произошло?
```postgresql
SELECT * FROM pg_stat_bgwriter;
```
```commandline
-[ RECORD 1 ]---------+-----------------------------
checkpoints_timed     | 24
checkpoints_req       | 3
checkpoint_write_time | 539429
checkpoint_sync_time  | 170
buffers_checkpoint    | 48131
buffers_clean         | 0
maxwritten_clean      | 0
buffers_backend       | 7654
buffers_backend_fsync | 0
buffers_alloc         | 8648
stats_reset           | 2025-02-03 16:47:55.35334+00
```

В логе:
```commandline
2025-02-03 17:23:38.064 UTC [224739] LOG:  checkpoint starting: time
2025-02-03 17:24:05.052 UTC [224739] LOG:  checkpoint complete: wrote 2090 buffers (12.8%); 0 WAL file(s) added, 0 removed, 2 recycled; write=26.954 s, sync=0.008 s, total=26.989 s; sync files=9, longest=0.004 s, average=0.001 s; distance=35126 kB, estimate=35775 kB
2025-02-03 17:24:08.055 UTC [224739] LOG:  checkpoint starting: time
2025-02-03 17:24:35.050 UTC [224739] LOG:  checkpoint complete: wrote 2938 buffers (17.9%); 0 WAL file(s) added, 0 removed, 2 recycled; write=26.960 s, sync=0.012 s, total=26.995 s; sync files=15, longest=0.005 s, average=0.001 s; distance=35274 kB, estimate=35725 kB
2025-02-03 17:25:08.083 UTC [224739] LOG:  checkpoint starting: time
2025-02-03 17:25:35.059 UTC [224739] LOG:  checkpoint complete: wrote 2028 buffers (12.4%); 0 WAL file(s) added, 0 removed, 2 recycled; write=26.963 s, sync=0.006 s, total=26.976 s; sync files=13, longest=0.002 s, average=0.001 s; distance=27508 kB, estimate=34904 kB
```

 - Время сохранения чекпоинта `~27 секунд` очень близко ко времени срабатывания чекпоинта по расписанию, возможно наложение.
 - Некоторые контрольные точки прошли вне расписания, но наложения по времени в логе не нашлось
 - Срабатывание чекпоинта может вызываться заполнением `max_wal_size`


### Сравните tps в синхронном/асинхронном режиме утилитой pgbench. Объясните полученный результат.

#### Синхронный режим
```commandline
SHOW synchronous_commit;
```
```commandline
 synchronous_commit 
--------------------
 on
(1 row)
```
```commandline
pgbench -P 1 -T 10 postgres
```
```commandline
pgbench (15.10 (Ubuntu 15.10-1.pgdg20.04+1))
starting vacuum...end.
progress: 1.0 s, 1203.9 tps, lat 0.828 ms stddev 0.183, 0 failed
progress: 2.0 s, 1220.0 tps, lat 0.819 ms stddev 0.322, 0 failed
progress: 3.0 s, 1238.0 tps, lat 0.807 ms stddev 0.160, 0 failed
progress: 4.0 s, 1253.0 tps, lat 0.798 ms stddev 0.166, 0 failed
progress: 5.0 s, 1236.0 tps, lat 0.809 ms stddev 0.166, 0 failed
progress: 6.0 s, 1212.0 tps, lat 0.825 ms stddev 0.130, 0 failed
progress: 7.0 s, 1168.0 tps, lat 0.856 ms stddev 0.249, 0 failed
progress: 8.0 s, 1210.0 tps, lat 0.826 ms stddev 0.185, 0 failed
progress: 9.0 s, 1193.0 tps, lat 0.838 ms stddev 0.169, 0 failed
progress: 10.0 s, 1269.0 tps, lat 0.787 ms stddev 0.152, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 10 s
number of transactions actually processed: 12204
number of failed transactions: 0 (0.000%)
latency average = 0.819 ms
latency stddev = 0.196 ms
initial connection time = 2.492 ms
tps = 1220.655849 (without initial connection time)
```

#### Асинхронный режим
Меняем настройку на весь кластер и перезагружаем:
```commandline
echo "synchronous_commit = off" >> /etc/postgresql/15/main/postgresql.conf
pg_ctlcluster 15 main stop
pg_ctlcluster 15 main start
```
Проверяем:
```postgresql
SHOW synchronous_commit;
```
```commandline
 synchronous_commit 
--------------------
 off
(1 row)
```
Нагружаем:
```commandline
pgbench -P 1 -T 10 postgres
```
```commandline
pgbench (15.10 (Ubuntu 15.10-1.pgdg20.04+1))
starting vacuum...end.
progress: 1.0 s, 3874.9 tps, lat 0.257 ms stddev 0.037, 0 failed
progress: 2.0 s, 4035.0 tps, lat 0.248 ms stddev 0.016, 0 failed
progress: 3.0 s, 4020.0 tps, lat 0.249 ms stddev 0.015, 0 failed
progress: 4.0 s, 4072.0 tps, lat 0.245 ms stddev 0.015, 0 failed
progress: 5.0 s, 3967.0 tps, lat 0.252 ms stddev 0.016, 0 failed
progress: 6.0 s, 3924.9 tps, lat 0.255 ms stddev 0.023, 0 failed
progress: 7.0 s, 3993.0 tps, lat 0.250 ms stddev 0.013, 0 failed
progress: 8.0 s, 3998.0 tps, lat 0.250 ms stddev 0.017, 0 failed
progress: 9.0 s, 3941.9 tps, lat 0.253 ms stddev 0.012, 0 failed
progress: 10.0 s, 3971.1 tps, lat 0.252 ms stddev 0.017, 0 failed
transaction type: <builtin: TPC-B (sort of)>
scaling factor: 1
query mode: simple
number of clients: 1
number of threads: 1
maximum number of tries: 1
duration: 10 s
number of transactions actually processed: 39799
number of failed transactions: 0 (0.000%)
latency average = 0.251 ms
latency stddev = 0.020 ms
initial connection time = 2.276 ms
tps = 3980.748297 (without initial connection time)
```
Разница в 3.3 раза.

Причина: реже пишем на диск, накапливая кеш в оперативке. 

Увеличиваем пропускную способность, рискуя консистентностью данных.


### Создайте новый кластер с включенной контрольной суммой страниц.
```commandline
pg_createcluster 15 test -p 5433 -- --data-checksums
echo "host all all 0.0.0.0/0 scram-sha-256" >> /etc/postgresql/15/test/pg_hba.conf
echo "listen_addresses = '*'" >> /etc/postgresql/15/test/postgresql.conf
pg_ctlcluster 15 test start
pg_lsclusters 
```
```commandline
15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
15  test    5433 online postgres /var/lib/postgresql/15/test /var/log/postgresql/postgresql-15-test.log
```
Проверяем:
```postgresql
SHOW data_checksums;
```
```commandline
 data_checksums 
----------------
 on
(1 row)
```

 - Создайте таблицу.
```postgresql
CREATE TABLE t(t1 text);
```
 - Вставьте несколько значений. 
```postgresql
INSERTT INTO t (t1) VALUES ('qwe'), ('asd'), ('zxc');
SELECT * FROM t ;
```
```commandline
 t1  
-----
 qwe
 asd
 zxc
(3 rows)
```
Запомним где находится директория с данными:
```postgresql
SHOW data_directory;
```
```commandline
       data_directory        
-----------------------------
 /var/lib/postgresql/15/test
(1 row)
```
И файл с таблицей:
```postgresql
SELECT pg_relation_filepath('t'::regclass);
```
```commandline
 pg_relation_filepath 
----------------------
 base/5/16388
```
Сам файл:
```commandline
$ ls -pla /var/lib/postgresql/15/test/base/5/16388 
-rw------- 1 postgres postgres 8192 Feb  3 19:51 /var/lib/postgresql/15/test/base/5/16388
```

 - Выключите кластер. 
```commandline
pg_ctlcluster 15 test stop
pg_lsclusters 
```
```commandline
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
15  test    5433 down   postgres /var/lib/postgresql/15/test /var/log/postgresql/postgresql-15-test.log
```

 - Измените пару байт в таблице. 

`vim` в помощь, в конце строки меняем читаемый символ `qwe` -> `qwa`

 - Включите кластер и сделайте выборку из таблицы. 
```commandline
pg_ctlcluster 15 test start
pg_lsclusters 
```
```commandline
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
15  test    5433 online postgres /var/lib/postgresql/15/test /var/log/postgresql/postgresql-15-test.log
```
Читаем:
```commandline
SELECT * FROM t ;
```
```commandline
WARNING:  page verification failed, calculated checksum 22810 but expected 53326
ERROR:  invalid page in block 0 of relation base/5/16388
```

 - ### Что и почему произошло? как проигнорировать ошибку и продолжить работу?
[https://postgresqlco.nf/doc/en/param/ignore_checksum_failure/](https://postgresqlco.nf/doc/en/param/ignore_checksum_failure/)

Чексумма не совпадает. 
Варианты:
 - выставить настройку `SET ignore_checksum_failure = on;`
```commandline
postgres=# SELECT * FROM t ;
WARNING:  page verification failed, calculated checksum 22810 but expected 53326
 t1  
-----
 qwa
 asd
 zxc
(3 rows)
```
 - Выставить настройку, позволяющую занулить поврежденные страницы (доверять таким данным мы не можем)

[https://www.postgresql.org/docs/current/runtime-config-developer.html#GUC-ZERO-DAMAGED-PAGES](https://www.postgresql.org/docs/current/runtime-config-developer.html#GUC-ZERO-DAMAGED-PAGES)
 
```commandline
SET zero_damaged_pages = on;
VACUUM FULL t;
SELECT * FROM t;
```
При этом поменяется файл с объектом таблицы БД:
```commandline
postgres=# SELECT pg_relation_filepath('t'::regclass);
 pg_relation_filepath 
----------------------
 base/5/16398
(1 row)
```
И будет потеряна вся невалидная страница, включающая все записи:
```commandline
postgres=# SELECT * FROM t;
 t1 
----
(0 rows)
```

