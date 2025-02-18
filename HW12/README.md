# HW 12. Резервное копирование и восстановление
 <hr>

### Подготовка
 - Создаем ВМ/докер c ПГ.

```
$ pg_lsclusters 
```
```commandline
Ver Cluster Port Status Owner    Data directory              Log file
15  main    5432 online postgres /var/lib/postgresql/15/main /var/log/postgresql/postgresql-15-main.log
```

### Создаем БД, схему и в ней таблицу.
```commandline
CREATE DATABASE otus;
\c otus
```
 - Заполним таблицы автосгенерированными 100 записями.

```commandline
CREATE TABLE student AS 
SELECT
  generate_series(1,10) AS id,
  md5(random()::text)::char(10) AS fio;
```
 - проверим:

```commandline
SELECT * FROM student;
```
```commandline
 id |    fio     
----+------------
  1 | 36189887b6
  2 | baaa8a2922
  3 | 5587f02c14
  4 | c132c9bcc3
  5 | 25bb934d5a
  6 | 110ffd1a74
  7 | 2d38a08089
  8 | 860c5ab7d0
  9 | dffce591dc
 10 | e60d11dbd8
(10 rows)
```

### Под линукс пользователем Postgres создадим каталог для бэкапов

```commandline
$ whoami && mkdir -p ~/backup && ls -pla ~/backup
```
```
postgres
total 8
drwxrwxr-x 2 postgres postgres 4096 Feb 18 16:09 ./
drwxr-xr-x 5 postgres postgres 4096 Feb 18 16:09 ../
```

### Сделаем логический бэкап используя утилиту COPY
 - требуется зайти в `psql` на сервере из-под пользователя `postgres`:
 - `psql -p 5432 -U postgres -d otus`

```commandline
\COPY student to '~/backup/20250218191145.otus.public.student.sql';
```
 - проверяем наличие файла с бэкапом
```commandline
$ cat ~/backup/20250218191145.otus.public.student.sql 
1	36189887b6
2	baaa8a2922
3	5587f02c14
4	c132c9bcc3
5	25bb934d5a
6	110ffd1a74
7	2d38a08089
8	860c5ab7d0
9	dffce591dc
10	e60d11dbd8
```
 - разделитель - `tab`

### Восстановим в 2 таблицу данные из бэкапа.
 - таблица должна существовать
 - `CREATE TABLE restored (id integer, fio text);`
```commandline
\COPY restored FROM '~/backup/20250218191145.otus.public.student.sql' WITH DELIMITER E'\t' ;
```
```commandline
SELECT * FROM restored;
```
```commandline
 id |    fio     
----+------------
  1 | 36189887b6
  2 | baaa8a2922
  3 | 5587f02c14
  4 | c132c9bcc3
  5 | 25bb934d5a
  6 | 110ffd1a74
  7 | 2d38a08089
  8 | 860c5ab7d0
  9 | dffce591dc
 10 | e60d11dbd8
(10 rows)
```

### Используя утилиту pg_dump создадим бэкап в кастомном сжатом формате двух таблиц

 - выполняется из командной строки linux
 - `pg_dump -d otus --create -U postgres` выводит в stdout `sql` текст, обрабатываем как считаем нужным

```commandline
pg_dump -d otus --create -U postgres -Fc > ~/backup/20250218195101.otus.sql.gz
```
и сравним размер архива с текстовым бэкапом:
```commandline
pg_dump -d otus --create -U postgres > ~/backup/20250218195212.otus.sql
```
```commandline
-rw-rw-r-- 1 postgres postgres 1924 Feb 18 16:51 20250218195101.otus.sql.gz
-rw-rw-r-- 1 postgres postgres 2092 Feb 18 16:52 20250218195212.otus.sql
```
```commandline
$ file 20250218195101.otus.sql.gz
20250218195101.otus.sql.gz: PostgreSQL custom database dump - v1.14-0
```
Если использовать `gzip`, то сжать можно еще сильнее, но формат будет отличаться. 
Для восстановления через `pg_restore` нужно использовать флаги `-Fc`

### Используя утилиту pg_restore восстановим в новую БД только вторую таблицу!

```commandline
CREATE DATABASE backup_db;
```
 - флагом `-t` указываем имена восстанавливаемых таблиц:
```commandline
pg_restore -d backup_db -U postgres -t restored ~/backup/20250218195101.otus.sql.gz
```
 - проверяем, подключившись к новой базе `backup_db`:

```commandline
$ psql -p 5432 -U postgres -d backup_db
psql (15.10 (Ubuntu 15.10-1.pgdg20.04+1))
Type "help" for help.

backup_db=# \dt+
                                    List of relations
 Schema |   Name   | Type  |  Owner   | Persistence | Access method | Size  | Description 
--------+----------+-------+----------+-------------+---------------+-------+-------------
 public | restored | table | postgres | permanent   | heap          | 16 kB | 
(1 row)
```
```commandline
SELECT * FROM restored;
```
```commandline
 id |    fio     
----+------------
  1 | 36189887b6
  2 | baaa8a2922
  3 | 5587f02c14
  4 | c132c9bcc3
  5 | 25bb934d5a
  6 | 110ffd1a74
  7 | 2d38a08089
  8 | 860c5ab7d0
  9 | dffce591dc
 10 | e60d11dbd8
(10 rows)
```
