# HW 13. Репликация
- реализовать свой миникластер на 3 ВМ. 
<hr>
 
### Подготовка


| имя ВМ      | IP            | port | database | tables                       |
|-------------|---------------|------|----------|------------------------------|
| postgres-00 | 172.17.210.17 | 5432 | hw13     | "test1" -> PUB               |
|             |               |      |          | "test2" <- SUB @ postgres-01 |
| postgres-01 | 172.17.210.18 | 5432 | hw13     | "test1" <- SUB @ postgres-00 |
|             |               |      |          | "test2" -> PUB               |
| postgres-02 | 172.17.210.19 | 5432 | hw13     | "test1" <- SUB @ postgres-00 |
|             |               |      |          | "test2" <- SUB @ postgres-01 |

На каждой виртуалке:
```commandline
echo "listen_addresses = '*'" >> /etc/postgresql/15/main/postgresql.conf
echo "host all all 0.0.0.0/0 md5" >> /etc/postgresql/15/main/pg_hba.conf
echo "wal_level = 'logical'" >> /etc/postgresql/15/main/postgresql.conf
echo "host replication all 0.0.0.0/0 md5" >> /etc/postgresql/15/main/pg_hba.conf

sudo systemctl restart postgresql
```
Создаем БД (на каждой VM):
```sql
CREATE DATABASE hw13;
\c hw13
```

 - На 1 ВМ создаем таблицы test1 для записи, test2 для запросов на чтение.
```sql
CREATE TABLE test1 (id INTEGER, content varchar(64));
CREATE TABLE test2 (id INTEGER, content varchar(64));
```
```commandline
hw13=# \d
         List of relations
 Schema | Name  | Type  |  Owner   
--------+-------+-------+----------
 public | test1 | table | postgres
 public | test2 | table | postgres
(2 rows)

hw13=# \d test1
                       Table "public.test1"
 Column  |         Type          | Collation | Nullable | Default 
---------+-----------------------+-----------+----------+---------
 id      | integer               |           |          | 
 content | character varying(64) |           |          | 

hw13=# \d test2
                       Table "public.test2"
 Column  |         Type          | Collation | Nullable | Default 
---------+-----------------------+-----------+----------+---------
 id      | integer               |           |          | 
 content | character varying(64) |           |          | 
```

 - Создаем публикацию таблицы test1 и подписываемся на публикацию таблицы test2 с ВМ №2.
```sql
CREATE PUBLICATION test_pub FOR TABLE test1;

CREATE SUBSCRIPTION test_sub
CONNECTION 'host=172.17.210.18 port=5432 user=postgres password=password dbname=hw13'
PUBLICATION test_pub WITH (copy_data = true);
```

 - На 2 ВМ создаем таблицы test2 для записи, test1 для запросов на чтение.
```sql
CREATE TABLE test1 (id INTEGER, content varchar(64));
CREATE TABLE test2 (id INTEGER, content varchar(64));
```

 - Создаем публикацию таблицы test2 и подписываемся на публикацию таблицы test1 с ВМ №1.
```sql
CREATE PUBLICATION test_pub FOR TABLE test2;

CREATE SUBSCRIPTION test_sub
CONNECTION 'host=172.17.210.17 port=5432 user=postgres password=password dbname=hw13'
PUBLICATION test_pub WITH (copy_data = true);
```

 - 3 ВМ использовать как реплику для чтения и бэкапов (подписаться на таблицы из ВМ №1 и №2 ).
> Таблицы уже должны существовать, поэтому создаем их
```
CREATE TABLE test1 (id INTEGER, content varchar(64));
CREATE TABLE test2 (id INTEGER, content varchar(64));
```
> Теперь создаем подписки
```sql
CREATE SUBSCRIPTION test_sub1
CONNECTION 'host=172.17.210.17 port=5432 user=postgres password=password dbname=hw13'
PUBLICATION test_pub WITH (copy_data = true);

CREATE SUBSCRIPTION test_sub2
CONNECTION 'host=172.17.210.18 port=5432 user=postgres password=password dbname=hw13'
PUBLICATION test_pub WITH (copy_data = true);
```
На каждую подписку необходим свой слот репликации. Необходимо убедиться что их достаточное кол-во в `max_wal_senders`

### Проверяем

1. Пишем в `postgres-00`, читаем на остальных

 - `postgres-00` VM
```sql
INSERT INTO test1 (id, content) VALUES (1, 'some text in first table');
```

 - `postgres-01` и `postgres-02` VMs
```sql
SELECT * FROM test1;
```
```commandline
hw13=# SELECT * FROM test1;
 id |         content          
----+--------------------------
  1 | some text in first table
(1 row)
```
2. Пишем в `postgres-01` VM, читаем на остальных

```sql
INSERT INTO test2 (id, content) VALUES (1, 'random text in second table');
```

 - `postgres-00` и `postgres-02` VMs
```sql
SELECT * FROM test2;
```
```commandline
hw13=# SELECT * FROM test2;
 id |           content           
----+-----------------------------
  1 | random text in second table
(1 row)
```
