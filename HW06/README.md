# HW 06. Механизм блокировок

### Подготовка

Поднимаем инстанс постгреса <u>без изменений дефолтных настроек</u>, см. [docker-compose.yml](docker-compose.yml):
```commandline
docker-compose -f docker-compose.yml up -d
```
Проверяем доступность:
```commandline
psql -h 192.168.1.254 -p 5432 -U otus -d otusdb
```
```commandline
Password for user otus: 
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
Type "help" for help.

otusdb=# 
```
Подготовим базу:
```commandline
otusdb=# create database locks;
CREATE DATABASE
otusdb=# \c locks
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
You are now connected to database "locks" as user "otus".

locks=# \l
                             List of databases
   Name    | Owner | Encoding |  Collate   |   Ctype    | Access privileges 
-----------+-------+----------+------------+------------+-------------------
 locks     | otus  | UTF8     | en_US.utf8 | en_US.utf8 | 
 otusdb    | otus  | UTF8     | en_US.utf8 | en_US.utf8 | 
 postgres  | otus  | UTF8     | en_US.utf8 | en_US.utf8 | 
 template0 | otus  | UTF8     | en_US.utf8 | en_US.utf8 | =c/otus          +
           |       |          |            |            | otus=CTc/otus
 template1 | otus  | UTF8     | en_US.utf8 | en_US.utf8 | =c/otus          +
           |       |          |            |            | otus=CTc/otus
(5 rows)

locks=# \du
                                   List of roles
 Role name |                         Attributes                         | Member of 
-----------+------------------------------------------------------------+-----------
 otus      | Superuser, Create role, Create DB, Replication, Bypass RLS | {}

locks=# CREATE TABLE accounts(
acc_no integer PRIMARY KEY,
amount numeric
);
CREATE TABLE

locks=# INSERT INTO accounts VALUES (1,1000.00), (2,2000.00), (3,3000.00);
INSERT 0 3

locks=# SELECT * FROM accounts;
 acc_no | amount  
--------+---------
      1 | 1000.00
      2 | 2000.00
      3 | 3000.00
(3 rows)

locks=# \dt+
                    List of relations
 Schema |   Name   | Type  | Owner | Size  | Description 
--------+----------+-------+-------+-------+-------------
 public | accounts | table | otus  | 16 kB | 
(1 row)

locks=# 
```


## Задания

По мотивам [https://habr.com/ru/companies/postgrespro/articles/500714/](https://habr.com/ru/companies/postgrespro/articles/500714/)

### Настройте сервер так, чтобы в журнал сообщений сбрасывалась информация о блокировках, удерживаемых более 200 миллисекунд. Воспроизведите ситуацию, при которой в журнале появятся такие сообщения.

Настройка производится параметром `log_lock_waits`.

В журнал сообщений сервера будет попадать информация, если транзакция ждала дольше, чем `deadlock_timeout`
 - несмотря на название параметра, речь идет об обычных waits

```commandline
locks=# show log_lock_waits;
 log_lock_waits 
----------------
 off
(1 row)
```
Переключаем на логирование:
```commandline
locks=# ALTER SYSTEM SET log_lock_waits = on;
ALTER SYSTEM
locks=# SELECT pg_reload_conf();
 pg_reload_conf 
----------------
 t
(1 row)

locks=# show log_lock_waits;
 log_lock_waits 
----------------
 on
(1 row)
```
 - лог находится в `/var/log/postgresql/postgresql-<VERSION>-main.log`
 - в docker container лог пишется в STDOUT: `docker logs -f postgres`

Экспортеры метрик могут сильно шуметь в логи некорректными\частыми запросами. Их можно отфильтровать:
```commandline
docker logs -f postgres 2>&1 \
  | grep -v "column \"total_time\" does not exist" \
  | grep -v "STATEMENT:  SELECT t2.rolname, t3.datname, queryid, calls, total_time"
```

Текущее значение таймаута:
```commandline
locks=# SHOW deadlock_timeout;
 deadlock_timeout 
------------------
 1s
(1 row)
```
Меняем (см. [https://edu.postgrespro.ru/dba2/dba2_12_locks_objects_lab.html](https://edu.postgrespro.ru/dba2/dba2_12_locks_objects_lab.html))
```commandline 
ALTER SYSTEM SET deadlock_timeout = '200ms';
SELECT pg_reload_conf();
SHOW deadlock_timeout;
```
```commandline
locks=# SHOW deadlock_timeout;
 deadlock_timeout 
------------------
 200ms
(1 row)
```

В логе видим произошедшие изменения:
```commandline
2025-01-11 08:58:49.212 UTC [1] LOG:  received SIGHUP, reloading configuration files
2025-01-11 08:58:49.214 UTC [1] LOG:  parameter "deadlock_timeout" changed to "200ms"
```

Воспроизведем блокировку

 - Terminal **1**
```commandline
BEGIN;
UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;
```
 - Terminal **2**
```commandline
BEGIN;
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
```

Вторая команда UPDATE ожидает блокировку. Подождем секунду и завершим первую транзакцию.
 - Terminal **1**
```commandline
SELECT pg_sleep(10);
COMMIT;
```

Теперь и вторая транзакция может завершиться
 - Terminal **2**
```commandline
COMMIT;
```
Сообщения в логе:
```commandline
2025-01-11 09:34:40.014 UTC [3806] LOG:  process 3806 still waiting for ShareLock on transaction 741 after 200.067 ms
2025-01-11 09:34:40.014 UTC [3806] DETAIL:  Process holding the lock: 281. Wait queue: 3806.
2025-01-11 09:34:40.014 UTC [3806] CONTEXT:  while updating tuple (0,1) in relation "accounts"
2025-01-11 09:34:40.014 UTC [3806] STATEMENT:  UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
2025-01-11 09:37:48.528 UTC [3806] LOG:  process 3806 acquired ShareLock on transaction 741 after 188713.850 ms
2025-01-11 09:37:48.528 UTC [3806] CONTEXT:  while updating tuple (0,1) in relation "accounts"
2025-01-11 09:37:48.528 UTC [3806] STATEMENT:  UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
```

### Смоделируйте ситуацию обновления одной и той же строки тремя командами UPDATE в разных сеансах. Изучите возникшие блокировки в представлении pg_locks и убедитесь, что все они понятны. Пришлите список блокировок и объясните, что значит каждая.

Опираясь на подсказки, построим представление над `pg_locks`.
 - сделаем вывод чуть более компактным
 - ограничимся только интересными блокировками 
 - отбрасываем блокировки виртуальных номеров транзакций, индекса на таблице accounts, pg_locks и самого представления
```commandline
CREATE VIEW locks_v AS
SELECT pid,
       locktype,
       CASE locktype
         WHEN 'relation' THEN relation::regclass::text
         WHEN 'transactionid' THEN transactionid::text
         WHEN 'tuple' THEN relation::regclass::text||':'||tuple::text
       END AS lockid,
       mode,
       granted
FROM pg_locks
WHERE locktype in ('relation','transactionid','tuple')
AND (locktype != 'relation' OR relation = 'accounts'::regclass);
```






Начнем первую транзакцию и обновим строку.
 - Terminal **1**:
```commandline
BEGIN;
SELECT txid_current(), pg_backend_pid();

UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
SELECT * FROM locks_v WHERE pid = 281;
```
```commandline
locks=# SELECT * FROM locks_v WHERE pid = 281;
 pid |   locktype    |  lockid  |       mode       | granted 
-----+---------------+----------+------------------+---------
 281 | relation      | accounts | RowExclusiveLock | t
 281 | transactionid | 744      | ExclusiveLock    | t
(2 rows)


```
Транзакция удерживает блокировку таблицы и собственного номера.

Начинаем вторую транзакцию и пытаемся обновить ту же строку.
 - Terminal **2**:
```commandline
BEGIN;
SELECT txid_current(), pg_backend_pid();
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
```

 - Terminal **1**:
```commandline
 SELECT * FROM locks_v WHERE pid = 3806;
```
```commandline
locks=# SELECT * FROM locks_v WHERE pid = 3806;
 pid  |   locktype    |   lockid   |       mode       | granted 
------+---------------+------------+------------------+---------
 3806 | relation      | accounts   | RowExclusiveLock | t
 3806 | transactionid | 744        | ShareLock        | f
 3806 | tuple         | accounts:5 | ExclusiveLock    | t
 3806 | transactionid | 745        | ExclusiveLock    | t
(4 rows)

```
Помимо блокировки таблицы и собственного номера, мы видим еще две блокировки. 
Вторая транзакция обнаружила, что строка заблокирована первой и «повисла» на ожидании ее номера (granted = f). 
Но откуда и зачем взялась блокировка версии строки (locktype = tuple)?

Что произойдет, если появится третья аналогичная транзакция? Она попытается захватить блокировку версии строки и повиснет уже на этом шаге. Проверим.
 - Terminal **3**:
```commandline
BEGIN;
SELECT txid_current(), pg_backend_pid();
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
```

 - Terminal **1**
```commandline
 SELECT * FROM locks_v WHERE pid = 8131;
```
```commandline
locks=# SELECT * FROM locks_v WHERE pid = 8131;
 pid  |   locktype    |   lockid   |       mode       | granted 
------+---------------+------------+------------------+---------
 8131 | relation      | accounts   | RowExclusiveLock | t
 8131 | transactionid | 746        | ExclusiveLock    | t
 8131 | tuple         | accounts:5 | ExclusiveLock    | f
(3 rows)


```

Общую картину текущих ожиданий можно увидеть в представлении `pg_stat_activity`, добавив информацию о блокирующих процессах:
 - Terminal **4**
```commandline
SELECT pid, wait_event_type, wait_event, pg_blocking_pids(pid)
FROM pg_stat_activity
WHERE backend_type = 'client backend' ORDER BY pid;
```
```commandline
 pid  | wait_event_type |  wait_event   | pg_blocking_pids 
------+-----------------+---------------+------------------
   69 | Client          | ClientRead    | {}
  281 | Client          | ClientRead    | {}
 3806 | Lock            | transactionid | {281}
 8131 | Lock            | tuple         | {3806}
 9917 |                 |               | {}
(5 rows)

```
```commandline
locks=# SELECT * FROM locks_v WHERE pid = 281;
 pid |   locktype    |  lockid  |       mode       | granted 
-----+---------------+----------+------------------+---------
 281 | relation      | accounts | RowExclusiveLock | t
 281 | transactionid | 744      | ExclusiveLock    | t
(2 rows)

locks=# SELECT * FROM locks_v WHERE pid = 3806;
 pid  |   locktype    |   lockid   |       mode       | granted 
------+---------------+------------+------------------+---------
 3806 | relation      | accounts   | RowExclusiveLock | t
 3806 | transactionid | 744        | ShareLock        | f
 3806 | tuple         | accounts:5 | ExclusiveLock    | t
 3806 | transactionid | 745        | ExclusiveLock    | t
(4 rows)

locks=# SELECT * FROM locks_v WHERE pid = 8131;
 pid  |   locktype    |   lockid   |       mode       | granted 
------+---------------+------------+------------------+---------
 8131 | relation      | accounts   | RowExclusiveLock | t
 8131 | transactionid | 746        | ExclusiveLock    | t
 8131 | tuple         | accounts:5 | ExclusiveLock    | f
(3 rows)


```
Получается своеобразная «очередь», в которой есть первый (тот, кто удерживает блокировку версии строки) и все остальные, выстроившиеся за первым.

В логе эти события будут отражены:
```commandline
2025-01-11 11:05:36.680 UTC [3806] LOG:  process 3806 still waiting for ShareLock on transaction 744 after 200.029 ms
2025-01-11 11:05:36.680 UTC [3806] DETAIL:  Process holding the lock: 281. Wait queue: 3806.
2025-01-11 11:05:36.680 UTC [3806] CONTEXT:  while updating tuple (0,5) in relation "accounts"
2025-01-11 11:05:36.680 UTC [3806] STATEMENT:  UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
2025-01-11 11:07:12.713 UTC [8131] LOG:  process 8131 still waiting for ExclusiveLock on tuple (0,5) of relation 16421 of database 16420 after 200.166 ms
2025-01-11 11:07:12.713 UTC [8131] DETAIL:  Process holding the lock: 3806. Wait queue: 8131.
2025-01-11 11:07:12.713 UTC [8131] STATEMENT:  UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
```

Завершим все транзакции:
 - Terminal **1**, **2**, **3**
```commandline
COMMIT;
```
В логе увидим последовательное снятие блокировок:
```commandline
2025-01-11 11:24:11.349 UTC [3806] LOG:  process 3806 acquired ShareLock on transaction 744 after 1114869.674 ms
2025-01-11 11:24:11.349 UTC [3806] CONTEXT:  while updating tuple (0,5) in relation "accounts"
2025-01-11 11:24:11.349 UTC [3806] STATEMENT:  UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
2025-01-11 11:24:11.349 UTC [8131] LOG:  process 8131 acquired ExclusiveLock on tuple (0,5) of relation 16421 of database 16420 after 1018836.421 ms
2025-01-11 11:24:11.349 UTC [8131] STATEMENT:  UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
2025-01-11 11:24:11.549 UTC [8131] LOG:  process 8131 still waiting for ShareLock on transaction 745 after 200.027 ms
2025-01-11 11:24:11.549 UTC [8131] DETAIL:  Process holding the lock: 3806. Wait queue: 8131.
2025-01-11 11:24:11.549 UTC [8131] CONTEXT:  while rechecking updated tuple (0,6) in relation "accounts"
2025-01-11 11:24:11.549 UTC [8131] STATEMENT:  UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
2025-01-11 11:24:14.348 UTC [8131] LOG:  process 8131 acquired ShareLock on transaction 745 after 2998.582 ms
2025-01-11 11:24:14.348 UTC [8131] CONTEXT:  while rechecking updated tuple (0,6) in relation "accounts"
2025-01-11 11:24:14.348 UTC [8131] STATEMENT:  UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 1;
```

Полученные блокировки:
 - `RowExclusiveLock`, она же `ROW EXCLUSIVE`
```commandline
Конфликтует с режимами блокировки SHARE, SHARE ROW EXCLUSIVE, EXCLUSIVE и ACCESS EXCLUSIVE.
Команды UPDATE, DELETE и INSERT получают такую блокировку для целевой таблицы 
(в дополнение к блокировкам ACCESS SHARE для всех других задействованных таблиц). 
Вообще говоря, блокировку в этом режиме получает любая команда, которая изменяет данные в таблице.
```
 - `ExclusiveLock`, она же `EXCLUSIVE`
```commandline
Конфликтует с режимами блокировки ROW SHARE, ROW EXCLUSIVE, SHARE UPDATE EXCLUSIVE, SHARE, 
SHARE ROW EXCLUSIVE, EXCLUSIVE и ACCESS EXCLUSIVE. 
Этот режим совместим только с блокировкой ACCESS SHARE, то есть параллельно с транзакцией, 
получившей блокировку в этом режиме, допускается только чтение таблицы.
Запрашивается командой REFRESH MATERIALIZED VIEW CONCURRENTLY.
```
 - `ShareLock`, она же `SHARE`
```commandline
Конфликтует с режимами блокировки ROW EXCLUSIVE, SHARE UPDATE EXCLUSIVE, SHARE ROW EXCLUSIVE, 
EXCLUSIVE и ACCESS EXCLUSIVE. Этот режим защищает таблицу от параллельного изменения данных.
Запрашивается командой CREATE INDEX (без параметра CONCURRENTLY).
```
Описание блокировок: [https://postgrespro.ru/docs/postgrespro/10/explicit-locking](https://postgrespro.ru/docs/postgrespro/10/explicit-locking)

Таблица взаимоотношения блокировок: [https://postgrespro.ru/docs/postgrespro/10/explicit-locking#TABLE-LOCK-COMPATIBILITY](https://postgrespro.ru/docs/postgrespro/10/explicit-locking#TABLE-LOCK-COMPATIBILITY)


### Воспроизведите взаимоблокировку трех транзакций. Можно ли разобраться в ситуации постфактум, изучая журнал сообщений?

Пример разобран тут: [https://www.ibm.com/docs/en/db2-for-zos/12?topic=scenarios-scenario-three-way-deadlock-three-resources](https://www.ibm.com/docs/en/db2-for-zos/12?topic=scenarios-scenario-three-way-deadlock-three-resources)

 - Terminal **1**
```commandline
BEGIN;
UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;
```

 - Terminal **2**
```commandline
BEGIN;
UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 2;
```

 - Terminal **3**
```commandline
BEGIN;
UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 3;
```

 - Terminal **1**
```commandline
UPDATE accounts SET amount = amount + 50 WHERE acc_no = 2;
```

 - Terminal **2**
```commandline
UPDATE accounts SET amount = amount + 50 WHERE acc_no = 3;
```

 - Terminal **3**
```commandline
UPDATE accounts SET amount = amount + 50 WHERE acc_no = 1;
```
И тут мы увидим deadlock:
```commandline
ERROR:  deadlock detected
DETAIL:  Process 8131 waits for ShareLock on transaction 747; blocked by process 281.
Process 281 waits for ShareLock on transaction 748; blocked by process 3806.
Process 3806 waits for ShareLock on transaction 749; blocked by process 8131.
HINT:  See server log for query details.
CONTEXT:  while updating tuple (0,8) in relation "accounts"
```

В логе будет соответствующие сообщения:
```commandline
2025-01-11 12:44:06.641 UTC [281] LOG:  process 281 still waiting for ShareLock on transaction 748 after 200.147 ms
2025-01-11 12:44:06.641 UTC [281] DETAIL:  Process holding the lock: 3806. Wait queue: 281.
2025-01-11 12:44:06.641 UTC [281] CONTEXT:  while updating tuple (0,2) in relation "accounts"
2025-01-11 12:44:06.641 UTC [281] STATEMENT:  UPDATE accounts SET amount = amount + 50 WHERE acc_no = 2;
2025-01-11 12:44:15.967 UTC [3806] LOG:  process 3806 still waiting for ShareLock on transaction 749 after 200.031 ms
2025-01-11 12:44:15.967 UTC [3806] DETAIL:  Process holding the lock: 8131. Wait queue: 3806.
2025-01-11 12:44:15.967 UTC [3806] CONTEXT:  while updating tuple (0,3) in relation "accounts"
2025-01-11 12:44:15.967 UTC [3806] STATEMENT:  UPDATE accounts SET amount = amount + 50 WHERE acc_no = 3;
2025-01-11 12:44:31.433 UTC [8131] LOG:  process 8131 detected deadlock while waiting for ShareLock on transaction 747 after 200.067 ms
2025-01-11 12:44:31.433 UTC [8131] DETAIL:  Process holding the lock: 281. Wait queue: .
2025-01-11 12:44:31.433 UTC [8131] CONTEXT:  while updating tuple (0,8) in relation "accounts"
2025-01-11 12:44:31.433 UTC [8131] STATEMENT:  UPDATE accounts SET amount = amount + 50 WHERE acc_no = 1;
2025-01-11 12:44:31.433 UTC [8131] ERROR:  deadlock detected
2025-01-11 12:44:31.433 UTC [8131] DETAIL:  Process 8131 waits for ShareLock on transaction 747; blocked by process 281.
	Process 281 waits for ShareLock on transaction 748; blocked by process 3806.
	Process 3806 waits for ShareLock on transaction 749; blocked by process 8131.
	Process 8131: UPDATE accounts SET amount = amount + 50 WHERE acc_no = 1;
	Process 281: UPDATE accounts SET amount = amount + 50 WHERE acc_no = 2;
	Process 3806: UPDATE accounts SET amount = amount + 50 WHERE acc_no = 3;
2025-01-11 12:44:31.433 UTC [8131] HINT:  See server log for query details.
2025-01-11 12:44:31.433 UTC [8131] CONTEXT:  while updating tuple (0,8) in relation "accounts"
2025-01-11 12:44:31.433 UTC [8131] STATEMENT:  UPDATE accounts SET amount = amount + 50 WHERE acc_no = 1;
2025-01-11 12:44:31.434 UTC [3806] LOG:  process 3806 acquired ShareLock on transaction 749 after 15666.266 ms
2025-01-11 12:44:31.434 UTC [3806] CONTEXT:  while updating tuple (0,3) in relation "accounts"
2025-01-11 12:44:31.434 UTC [3806] STATEMENT:  UPDATE accounts SET amount = amount + 50 WHERE acc_no = 3;
```

Во всех трех терминалах закончим транзакции откатом:
 - Terminal **1**, **2**, **3**:
```commandline
ROLLBACK;
```

### Могут ли две транзакции, выполняющие единственную команду UPDATE одной и той же таблицы (без where), заблокировать друг друга?

Этот случай разбирали в лекции, упрощенный вариант предыдущего задания.

Подробности с вариантом объяснения [https://www.ibm.com/docs/en/db2-for-zos/12?topic=scenarios-scenario-two-way-deadlock-two-resources](https://www.ibm.com/docs/en/db2-for-zos/12?topic=scenarios-scenario-two-way-deadlock-two-resources)


 - Terminal **1**
Проверим параметры 
```commandline
SHOW deadlock_timeout;
SHOW lock_timeout;
```
```commandline
locks=# SHOW deadlock_timeout;
 deadlock_timeout 
------------------
 200ms
(1 row)

locks=# SHOW lock_timeout;
 lock_timeout 
--------------
 0
(1 row)
```

Первая транзакция намерена перенести 100 рублей с первого счета на второй. 
Для этого она сначала уменьшает первый счет
```commandline
BEGIN;
UPDATE accounts SET amount = amount - 100.00 WHERE acc_no = 1;
```

В это же время вторая транзакция намерена перенести 10 рублей со второго счета на первый. 
Она начинает с того, что уменьшает второй счет:
 - Terminal **2**
```commandline
BEGIN;
UPDATE accounts SET amount = amount - 10.00 WHERE acc_no = 2;
```

 - Terminal **1** 
```commandline
UPDATE accounts SET amount = amount + 100.00 WHERE acc_no = 2;
```

-- Session #2
 - Terminal **2**
```commandline
UPDATE accounts SET amount = amount + 10.00 WHERE acc_no = 1;
```
Возникает циклическое ожидание, который никогда не завершится само по себе. 
Через секунду первая транзакция, не получив доступ к ресурсу, инициирует проверку взаимоблокировки и обрывается сервером.

```commandline
ROLLBACK;
```

 - Terminal **1**
```commandline
ROLLBACK;
```
