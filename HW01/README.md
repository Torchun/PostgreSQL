# HW 01

## Задания

### Выключить auto commit
Старутем две сессии:
```
$ docker run --rm -ti postgres:15.10 psql -h 192.168.1.254 -p 5432 -U otus -d otusdb
```

В первой сессии:
```
otusdb=# \set AUTOCOMMIT off
otusdb=# \echo :AUTOCOMMIT
off
```

### Cделать в первой сессии новую таблицу и наполнить ее данными
```
create table persons(id serial, first_name text, second_name text);
insert into persons(first_name, second_name) values('ivan', 'ivanov');
insert into persons(first_name, second_name) values('petr', 'petrov');
commit;
```
Результат:
```
otusdb=# create table persons(id serial, first_name text, second_name text);
insert into persons(first_name, second_name) values('ivan', 'ivanov');
insert into persons(first_name, second_name) values('petr', 'petrov'); 
CREATE TABLE
INSERT 0 1
INSERT 0 1
otusdb=*# commit;
COMMIT

```

### Посмотреть текущий уровень изоляции

```
show transaction isolation level;
```

Результат:
```
otusdb=# show transaction isolation level;
 transaction_isolation 
-----------------------
 read committed
(1 row)

```

### Работа с коммитами транзакций
Сессия **1**:
```
insert into persons(first_name, second_name) values('sergey', 'sergeev');
select * from persons;
```
```
otusdb=# insert into persons(first_name, second_name) values('sergey', 'sergeev');
INSERT 0 1
otusdb=*# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  5 | sergey     | sergeev
(3 rows)

otusdb=*# 

```
Сессия **2**:
```
select * from persons;
```
```
otusdb=# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
(2 rows)

otusdb=*# 

```
Во второй сессии запись не видна, т.к. не было коммита, и по `show transaction isolation level` = `read committed` будут прочтены только `commited` данные.
Незакомиченные транзакции порождают ошибку по таймауту:
```
FATAL:  terminating connection due to idle-in-transaction timeout
server closed the connection unexpectedly
	This probably means the server terminated abnormally
	before or while processing the request.
The connection to the server was lost. Attempting reset: Succeeded.
```

Успеваем добавить коммит в сессию **1**

Сессия **1**:
```
commit;
select * from persons;
```
```
otusdb=*# commit;
select * from persons;
COMMIT
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  6 | sergey     | sergeev
(3 rows)
```

Сессия **2**:
```
select * from persons;
```
```
otusdb=*# select * from persons;
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  6 | sergey     | sergeev
(3 rows)

otusdb=*# 
```
В сессии **2** даже в рамках одной транзакции виден результат коммита сессии **1**

### Repeatable read транзации

Сессия **1**:
```
set transaction isolation level repeatable read;
insert into persons(first_name, second_name) values('sveta', 'svetova');
show transaction isolation level;
```

```
otusdb=# set transaction isolation level repeatable read;
insert into persons(first_name, second_name) values('sveta', 'svetova');
show transaction isolation level;
SET
INSERT 0 1
 transaction_isolation 
-----------------------
 repeatable read
(1 row)

otusdb=*# 
```

Сессия **2**:
```
set transaction isolation level repeatable read;
select * from persons; 
show transaction isolation level;
```

```
otusdb=# set transaction isolation level repeatable read;
select * from persons;
show transaction isolation level;
SET
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  6 | sergey     | sergeev
(3 rows)

 transaction_isolation 
-----------------------
 repeatable read
(1 row)

otusdb=*# 
```

В сессии **2** новой записи не видно.

Успеваем сделать коммит в сессии **1** до срабатывания таймаута:
```
otusdb=*# commit;
COMMIT
```

Во второй сессии в рамках той же транзакции (до срабатывания таймаута) успеваем сделать:
```
select * from persons;
```
Записи все еще не видно:
```
otusdb=*# select * from persons;
 id | first_name | second_name
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  6 | sergey     | sergeev
(3 rows)

otusdb=*#

```
Успеваем в сессии **2** сделать `commit`:
```
otusdb=*# commit;
COMMIT
```

Теперь в сессии **2** (но уже в следующей транзакции) запись видна:
```
otusdb=# set transaction isolation level repeatable read;
select * from persons;
show transaction isolation level;
SET
 id | first_name | second_name 
----+------------+-------------
  1 | ivan       | ivanov
  2 | petr       | petrov
  6 | sergey     | sergeev
 13 | sveta      | svetova
(4 rows)

 transaction_isolation 
-----------------------
 repeatable read
(1 row)

otusdb=*# 
```

Причина такого поведения: разница "read commited" vs "repeatable read" настроек транзакции

Подробнее: 
 - [READ-COMMITTED](https://www.postgresql.org/docs/current/transaction-iso.html#XACT-READ-COMMITTED)
 - [REPEATABLE-READ](https://www.postgresql.org/docs/current/transaction-iso.html#XACT-REPEATABLE-READ)


