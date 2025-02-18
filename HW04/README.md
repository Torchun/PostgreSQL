# HW 04. Работа с базами данных, пользователями и правами

## Задания

### создание кластера PostgresSQL 15
```commandline
cd infra
docker-compose -f docker-compose.yml up -d
```
```commandline
$ docker ps -a 
CONTAINER ID   IMAGE              COMMAND                  CREATED              STATUS                        PORTS                                      NAMES
ebc1d6d09f55   postgres:15.10     "docker-entrypoint.s…"   About a minute ago   Up About a minute (healthy)   0.0.0.0:5432->5432/tcp, :::5432->5432/tcp  postgres
```
### Работа с DB

 - зайдите в созданный кластер под пользователем postgres
```commandline
$ psql -h 0.0.0.0 -p 5432 -U postgres
Password for user postgres: 
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
Type "help" for help.

postgres=# 
```

 - создайте новую базу данных testdb
```commandline
postgres=# ﻿CREATE DATABASE testdb;
CREATE DATABASE
```
```commandline
postgres=# \l
                                 List of databases
   Name    |  Owner   | Encoding |  Collate   |   Ctype    |   Access privileges   
-----------+----------+----------+------------+------------+-----------------------
 postgres  | postgres | UTF8     | en_US.utf8 | en_US.utf8 | 
 template0 | postgres | UTF8     | en_US.utf8 | en_US.utf8 | =c/postgres          +
           |          |          |            |            | postgres=CTc/postgres
 template1 | postgres | UTF8     | en_US.utf8 | en_US.utf8 | =c/postgres          +
           |          |          |            |            | postgres=CTc/postgres
 testdb    | postgres | UTF8     | en_US.utf8 | en_US.utf8 | 
(4 rows)
```

 - зайдите в созданную базу данных под пользователем postgres
```commandline
postgres=# \c testdb
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
You are now connected to database "testdb" as user "postgres".
```

 - создайте новую схему testnm
```commandline
testdb=# CREATE SCHEMA testnm;
CREATE SCHEMA
testdb=# \dn
      List of schemas
  Name  |       Owner       
--------+-------------------
 public | pg_database_owner
 testnm | postgres
(2 rows)
```

 - создайте новую таблицу t1 с одной колонкой c1 типа integer
```commandline
testdb=# CREATE TABLE t1(c1 integer);
CREATE TABLE
testdb=# \dt
        List of relations
 Schema | Name | Type  |  Owner   
--------+------+-------+----------
 public | t1   | table | postgres
(1 row)
```

 - вставьте строку со значением c1=1
```commandline
testdb=# INSERT INTO t1 values(1);
INSERT 0 1
testdb=# SELECT * FROM t1;
 c1 
----
  1
(1 row)
```

 - создайте новую роль readonly
```commandline
testdb=# CREATE role readonly;
CREATE ROLE
testdb=# \du
                                   List of roles
 Role name |                         Attributes                         | Member of 
-----------+------------------------------------------------------------+-----------
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS | {}
 readonly  | Cannot login                                               | {}
```

 - дайте новой роли право на подключение к базе данных testdb
```commandline
testdb=# grant connect on DATABASE testdb TO readonly;
GRANT
```

 - дайте новой роли право на использование схемы testnm
```commandline
testdb=# grant usage on SCHEMA testnm to readonly;
GRANT
```

 - дайте новой роли право на select для всех таблиц схемы testnm
```commandline
testdb=# grant SELECT on all TABLEs in SCHEMA testnm TO readonly;
GRANT
```

 - создайте пользователя testread с паролем test123
```
testdb=# CREATE USER testread with password 'test123';
CREATE ROLE
testdb=# \du
                                   List of roles
 Role name |                         Attributes                         | Member of 
-----------+------------------------------------------------------------+-----------
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS | {}
 readonly  | Cannot login                                               | {}
 testread  |                                                            | {}
```

 - дайте роль readonly пользователю testread
```commandline
testdb=# grant readonly TO testread;
GRANT ROLE
testdb=# \du
                                    List of roles
 Role name |                         Attributes                         | Member of  
-----------+------------------------------------------------------------+------------
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS | {}
 readonly  | Cannot login                                               | {}
 testread  |                                                            | {readonly}
```

 - зайдите под пользователем testread в базу данных testdb
```commandline
testdb=# \c testdb testread
Password for user testread: 
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
You are now connected to database "testdb" as user "testread".
testdb=> 
```

 - сделайте select * from t1;
```commandline
testdb=> SELECT * FROM t1;
ERROR:  permission denied for table t1
```

 - напишите что именно произошло в тексте домашнего задания

Смотрим в привилегии от таблицы к пользователю (роли):
```commandline
testdb=> \d t1
                 Table "public.t1"
 Column |  Type   | Collation | Nullable | Default 
--------+---------+-----------+----------+---------
 c1     | integer |           |          | 
```
таблица `t1` создана в схеме `public`
```commandline
testdb=> \dn+
                                       List of schemas
  Name  |       Owner       |           Access privileges            |      Description       
--------+-------------------+----------------------------------------+------------------------
 public | pg_database_owner | pg_database_owner=UC/pg_database_owner+| standard public schema
        |                   | =U/pg_database_owner                   | 
 testnm | postgres          | postgres=UC/postgres                  +| 
        |                   | readonly=U/postgres                    | 
(2 rows)
```
роль `readonly` не имеет на нее прав
```commandline
testdb=> \du
                                    List of roles
 Role name |                         Attributes                         | Member of  
-----------+------------------------------------------------------------+------------
 postgres  | Superuser, Create role, Create DB, Replication, Bypass RLS | {}
 readonly  | Cannot login                                               | {}
 testread  |                                                            | {readonly}
```
И т.к. пользователь `testread` входит только в группу `readonly`, то и он унаследовал отсутствие прав.

По подсказке и описанию в 
[https://postgrespro.ru/docs/postgrespro/9.6/ddl-schemas#ddl-schemas-path](https://postgrespro.ru/docs/postgrespro/9.6/ddl-schemas#ddl-schemas-path)
```commandline
testdb=> SHOW search_path;
   search_path   
-----------------
 "$user", public
(1 row)
```
делаем  вывод что схемы `$USER` нет, и таблица по умолчанию создалась в public.

 - вернитесь в базу данных testdb под пользователем postgres
```commandline
testdb=> \c testdb postgres
Password for user postgres: 
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
You are now connected to database "testdb" as user "postgres".
testdb=# 
```

 - удалите таблицу t1
```commandline
testdb=# DROP TABLE t1;
DROP TABLE
```

 - создайте ее заново но уже с явным указанием имени схемы testnm
```commandline
testdb=# CREATE TABLE testnm.t1(c1 integer);
CREATE TABLE
```

 - вставьте строку со значением c1=1
```commandline
testdb=# INSERT INTO testnm.t1 values(1);
INSERT 0 1
```

 - зайдите под пользователем testread в базу данных testdb
```commandline
testdb=# \c testdb testread
Password for user testread: 
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
You are now connected to database "testdb" as user "testread".
testdb=> 
```

 - сделайте select * from testnm.t1;
```commandline
testdb=> select * from testnm.t1;
ERROR:  permission denied for table t1
```
_потому что grant SELECT on all TABLEs in SCHEMA testnm TO readonly дал доступ только для существующих на тот момент времени таблиц а t1 пересоздавалась_

 - как сделать так чтобы такое больше не повторялось? если нет идей - смотрите шпаргалку
```commandline
testdb=> \c testdb postgres; 
Password for user postgres: 
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
You are now connected to database "testdb" as user "postgres".

testdb=# ALTER default PRIVILEGES in SCHEMA testnm GRANT SELECT on TABLES to readonly; 
ALTER DEFAULT PRIVILEGES
```

 - сделайте select * from testnm.t1;
```commandline
testdb=# \c testdb testread
Password for user testread: 
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
You are now connected to database "testdb" as user "testread".

testdb=> select * from testnm.t1;
ERROR:  permission denied for table t1
```

 - есть идеи почему?

Причина та же - эффективно для новых сущностей.
Из шпаргалки:
```
потому что ALTER default будет действовать для новых таблиц 
grant SELECT on all TABLEs in SCHEMA testnm TO readonly
отработал только для существующих на тот момент времени. 
надо сделать снова или grant SELECT или пересоздать таблицу
```
Исправляем:
```commandline
testdb=> \c testdb postgres; 
Password for user postgres: 
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
You are now connected to database "testdb" as user "postgres".

testdb=# grant SELECT on all TABLEs in SCHEMA testnm TO readonly;
GRANT

testdb=# \c testdb testread
Password for user testread: 
psql (12.22 (Ubuntu 12.22-0ubuntu0.20.04.1), server 15.10 (Debian 15.10-1.pgdg120+1))
WARNING: psql major version 12, server major version 15.
         Some psql features might not work.
You are now connected to database "testdb" as user "testread".

testdb=> select * from testnm.t1;
 c1 
----
  1
(1 row)
```
Объяснение выше, +дубль из шпаргалки:
```commandline
это все потому что search_path указывает в первую очередь на схему public. 
А схема public создается в каждой базе данных по умолчанию. 
И grant на все действия в этой схеме дается роли public. 
А роль public добавляется всем новым пользователям. 
Соответсвенно каждый пользователь может по умолчанию создавать объекты в схеме public любой базы данных, 
ес-но если у него есть право на подключение к этой базе данных. 
```
Чтобы раз и навсегда забыть про роль public - а в продакшн базе данных про нее лучше забыть - выполните следующие действия 
```commandline
\c testdb postgres; 
REVOKE CREATE on SCHEMA public FROM public; 
REVOKE ALL on DATABASE testdb FROM public; 
\c testdb testread; 
```

 - теперь попробуйте выполнить команду create table t2(c1 integer); insert into t2 values (2);
```commandline
testdb=> create table t2(c1 integer); insert into t2 values (2);
ERROR:  permission denied for schema public
LINE 1: create table t2(c1 integer);
                     ^
ERROR:  relation "t2" does not exist
LINE 1: insert into t2 values (2);
                    ^
```
Причина из шпаргалки:
```commandline
в 15 версии права на CREATE TABLE по умолчанию отозваны у схемы PUBLIC, только USAGE
```
В версиях до 15 надо править вручную.

(примеры из шпаргалки):
```commandline
\c testdb postgres; 
REVOKE CREATE on SCHEMA public FROM public; 
REVOKE ALL on DATABASE testdb FROM public; 
\c testdb testread; 
```
Смысл действий:
 - отозвать права на создание таблиц в схеме `public`, т.е. пользователи будут получать ошибку как в примере выше
 - запрет на все действия с `testdb`, унаследованные от `public`

