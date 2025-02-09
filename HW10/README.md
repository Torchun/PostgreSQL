# HW 10
 <hr>

### Подготовка

На основе готовой базы данных примените один из методов секционирования в зависимости от структуры данных.

Данные: [https://postgrespro.ru/education/demodb](https://postgrespro.ru/education/demodb)

Установка: [https://postgrespro.ru/docs/postgrespro/15/demodb-bookings-installation](https://postgrespro.ru/docs/postgrespro/15/demodb-bookings-installation)

```commandline
psql -f /tmp/demo-small-20170815.sql -U postgres
```
```sql
\c demo
\dt+
```
```commandline
                                  List of relations
  Schema  |      Name       | Type  |  Owner   |  Size   |        Description        
----------+-----------------+-------+----------+---------+---------------------------
 bookings | aircrafts_data  | table | postgres | 16 kB   | Aircrafts (internal data)
 bookings | airports_data   | table | postgres | 56 kB   | Airports (internal data)
 bookings | boarding_passes | table | postgres | 33 MB   | Boarding passes
 bookings | bookings        | table | postgres | 13 MB   | Bookings
 bookings | flights         | table | postgres | 3168 kB | Flights
 bookings | seats           | table | postgres | 96 kB   | Seats
 bookings | ticket_flights  | table | postgres | 68 MB   | Flight segment
 bookings | tickets         | table | postgres | 48 MB   | Tickets
(8 rows)
```

## Анализ структуры данных

### Ознакомьтесь с таблицами базы данных, особенно с таблицами bookings, tickets, ticket_flights, flights, boarding_passes, seats, airports, aircrafts.

Функция для подсчета количества записей в таблице:
```sql
create function 
cnt_rows(schema text, tablename text) returns integer
as
$body$
declare
  result integer;
  query varchar;
begin
  query := 'SELECT count(1) FROM ' || schema || '.' || tablename;
  execute query into result;
  return result;
end;
$body$
language plpgsql;
```
И её вызов по каждой таблице:
```sql
select
  table_schema,
  table_name, 
  cnt_rows(table_schema, table_name)
from information_schema.tables
where 
  table_schema not in ('pg_catalog', 'information_schema') 
  and table_type='BASE TABLE'
order by 3 desc;
```
Результат:
```commandline
 table_schema |   table_name    | cnt_rows 
--------------+-----------------+----------
 bookings     | ticket_flights  |  1045726
 bookings     | boarding_passes |   579686
 bookings     | tickets         |   366733
 bookings     | bookings        |   262788
 bookings     | flights         |    33121
 bookings     | seats           |     1339
 bookings     | airports_data   |      104
 bookings     | aircrafts_data  |        9
(8 rows)
```

### Определите, какие данные в таблице bookings или других таблицах имеют логическую привязку к диапазонам, по которым можно провести секционирование (например, дата бронирования, рейсы).

Посмотрим на самые большие таблицы:
```commandline
SELECT * FROM ticket_flights LIMIT 1;
```
```commandline
   ticket_no   | flight_id | fare_conditions |  amount  
---------------+-----------+-----------------+----------
 0005432159776 |     30625 | Business        | 42100.00
```
```commandline
SELECT * FROM boarding_passes LIMIT 1;
```
```commandline
   ticket_no   | flight_id | boarding_no | seat_no 
---------------+-----------+-------------+---------
 0005435212351 |     30625 |           1 | 2D
```
```commandline
SELECT * FROM tickets LIMIT 1;
```
```commandline
   ticket_no   | book_ref | passenger_id |  passenger_name  |       contact_data        
---------------+----------+--------------+------------------+---------------------------
 0005432000987 | 06B046   | 8149 604011  | VALERIY TIKHONOV | {"phone": "+70127117011"}
```
```
SELECT * FROM bookings LIMIT 1;
```
```commandline
 book_ref |       book_date        | total_amount 
----------+------------------------+--------------
 00000F   | 2017-07-05 00:12:00+00 |    265700.00
```
Возможные кандидаты на секционирование:
 - номер рейса
 - дата бронирования
 - аэропорт вылета\прилета
 - номер места (`SELECT COUNT(DISTINCT seat_no) FROM boarding_passes;` = 461)
 - класс билета (Бизнес, комфорт, эконом)

## Выбор таблицы для секционирования

 - Основной акцент делается на секционировании таблицы `bookings`. Но вы можете выбрать и другие таблицы, если видите в этом смысл для оптимизации производительности (например, flights, boarding_passes).
 - Обоснуйте свой выбор: почему именно эта таблица требует секционирования? Какой тип данных является ключевым для секционирования?

При выборе категориального поля получаем бесконечно растущую в объеме секцию (==файл). Лучше выбрать поле с датой или уникальным номером.

Останавливаемся на таблице `bookings` (`book_date`)

```
SELECT * FROM bookings LIMIT 1;
```
```commandline
 book_ref |       book_date        | total_amount 
----------+------------------------+--------------
 00000F   | 2017-07-05 00:12:00+00 |    265700.00
```

## Определение типа секционирования

Определитесь с типом секционирования, которое наилучшим образом подходит для ваших данных:
 - По диапазону (например, по дате бронирования или дате рейса).
 - По списку (например, по пунктам отправления или по номерам рейсов).
 - По хэшированию (для равномерного распределения данных).

Таблица с датой бронирования, лучше всего подойдет секционирование по диапазону.


## Создание секционированной таблицы

 - Преобразуйте таблицу в секционированную с выбранным типом секционирования.
 - Например, если вы выбрали секционирование по диапазону дат бронирования, создайте секции по месяцам или годам.

Посмотрим на распределение записей по годам:
```commandline
SELECT DATE_PART('year', book_date::date) AS year, count(*)
FROM bookings
WHERE book_date is not NULL
GROUP BY year;
```
```commandline
 year | count  
------+--------
 2017 | 262788
(1 row)
```
Т.к. данных мало, а секционировать надо, выберем секционирование по месяцам:

```commandline
SELECT DATE_PART('month', book_date::date) AS month, count(*)
FROM bookings
WHERE book_date is not NULL
GROUP BY month;
```
```commandline
 month | count  
-------+--------
     6 |   7730
     8 |  87790
     7 | 167268
(3 rows)
```
Не смотря на сильную неравномерность, все еще оставляем секционирование по месяцам. 
В реальном мире требуется исследовать изменение распределения на более длинном отрезке времени, или выбрать секционирование по другому признаку.

Для создания партиций есть два пути:
 - использовать `inherits` для существующей таблицы. Потребуется создавать `CHECK` и триггеры. Не придется мигрировать данные.
 - Создать новую ьаблицу, которая партицирована по построению. Не нужно делать триггеры. Нужно мигрировать данные.

Выбиарем второй вариант, чтобы не писать триггеры.

Подсматриваем DDL таблицы:
```commandline
pg_dump -U postgres demo -t bookings --schema-only
```
```
...

CREATE TABLE bookings.bookings (
    book_ref character(6) NOT NULL,
    book_date timestamp with time zone NOT NULL,
    total_amount numeric(10,2) NOT NULL
);
ALTER TABLE ONLY bookings.bookings
    ADD CONSTRAINT bookings_pkey PRIMARY KEY (book_ref);
...
```
И дополняем нужной опцией для партицирования по полю `book_date`
```commandline
CREATE TABLE bookings_partitioned (
    book_ref     character(6) NOT NULL,
    book_date    timestamp with time zone NOT NULL,
    total_amount numeric(10,2) NOT NULL
) PARTITION BY RANGE (book_date);
```

Вручную создадим три партиции (по количеству месяцев):
 - `FROM` .. `TO` не включает последнее значение интервала
```commandline
CREATE TABLE bookings_2017_6 PARTITION OF bookings_partitioned FOR VALUES FROM ('2017-06-01') TO ('2017-07-01');
CREATE TABLE bookings_2017_7 PARTITION OF bookings_partitioned FOR VALUES FROM ('2017-07-01') TO ('2017-08-01');
CREATE TABLE bookings_2017_8 PARTITION OF bookings_partitioned FOR VALUES FROM ('2017-08-01') TO ('2017-09-01');
```


## Миграция данных

### Перенесите существующие данные из исходной таблицы в секционированную структуру.

```commandline
INSERT INTO bookings_partitioned (SELECT * FROM bookings);
```

### Убедитесь, что все данные правильно распределены по секциям.

```commandline
\dt+
```
```
                                          List of relations
  Schema  |         Name         |       Type        |  Owner   |  Size   |        Description        
----------+----------------------+-------------------+----------+---------+---------------------------
 ...
 bookings | bookings             | table             | postgres | 13 MB   | Bookings
 bookings | bookings_2017_6      | table             | postgres | 424 kB  | 
 bookings | bookings_2017_7      | table             | postgres | 8552 kB | 
 bookings | bookings_2017_8      | table             | postgres | 4504 kB | 
 bookings | bookings_partitioned | partitioned table | postgres | 0 bytes | 
```
```commandline
SELECT COUNT(*) FROM bookings_2017_7;
```
```commandline
 count  
--------
 167268
(1 row)
```
```commandline
SELECT COUNT(*) FROM bookings 
WHERE 
  book_date >= '2017-07-01' 
    AND 
  book_date < '2017-08-01'
;
```
```commandline
 count  
--------
 167268
(1 row)
```
Данные разложились по партициям правильно.


## Оптимизация запросов

### Проверьте, как секционирование влияет на производительность запросов. Выполните несколько выборок данных до и после секционирования для оценки времени выполнения.

```commandline
EXPLAIN ANALYZE
SELECT * FROM bookings WHERE book_ref = '000068';
```
```commandline
                                                       QUERY PLAN                                                        
-------------------------------------------------------------------------------------------------------------------------
 Index Scan using bookings_pkey on bookings  (cost=0.42..8.44 rows=1 width=21) (actual time=0.037..0.040 rows=1 loops=1)
   Index Cond: (book_ref = '000068'::bpchar)
 Planning Time: 0.221 ms
 Execution Time: 0.075 ms
(4 rows)
```

```commandline
EXPLAIN ANALYZE
SELECT * FROM bookings_partitioned WHERE book_ref = '000068';
```
```commandline
                                                                       QUERY PLAN                                                                        
---------------------------------------------------------------------------------------------------------------------------------------------------------
 Gather  (cost=1000.00..4608.58 rows=3 width=21) (actual time=0.531..9.903 rows=1 loops=1)
   Workers Planned: 2
   Workers Launched: 2
   ->  Parallel Append  (cost=0.00..3608.28 rows=3 width=21) (actual time=1.649..3.814 rows=0 loops=3)
         ->  Parallel Seq Scan on bookings_2017_7 bookings_partitioned_2  (cost=0.00..2295.91 rows=1 width=21) (actual time=3.674..3.674 rows=0 loops=2)
               Filter: (book_ref = '000068'::bpchar)
               Rows Removed by Filter: 83634
         ->  Parallel Seq Scan on bookings_2017_8 bookings_partitioned_3  (cost=0.00..1205.51 rows=1 width=21) (actual time=0.002..3.724 rows=1 loops=1)
               Filter: (book_ref = '000068'::bpchar)
               Rows Removed by Filter: 87789
         ->  Parallel Seq Scan on bookings_2017_6 bookings_partitioned_1  (cost=0.00..106.84 rows=1 width=21) (actual time=0.362..0.362 rows=0 loops=1)
               Filter: (book_ref = '000068'::bpchar)
               Rows Removed by Filter: 7730
 Planning Time: 0.060 ms
 Execution Time: 9.919 ms
```
Время поиска по секционированной таблице значительно больше.


### Оптимизируйте запросы при необходимости (например, добавьте индексы на ключевые столбцы).

Индексы создаются на партиции:
```commandline
CREATE INDEX CONCURRENTLY bookings_2017_6_book_ref_idx ON bookings_2017_6 USING BTREE (book_ref);
CREATE INDEX CONCURRENTLY bookings_2017_7_book_ref_idx ON bookings_2017_7 USING BTREE (book_ref);
CREATE INDEX CONCURRENTLY bookings_2017_8_book_ref_idx ON bookings_2017_8 USING BTREE (book_ref);
```
```commandline
                                                                                 QUERY PLAN                                                                                 
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------
 Append  (cost=0.28..25.06 rows=3 width=21) (actual time=0.033..0.035 rows=1 loops=1)
   ->  Index Scan using bookings_2017_6_book_ref_idx on bookings_2017_6 bookings_partitioned_1  (cost=0.28..8.30 rows=1 width=21) (actual time=0.016..0.016 rows=0 loops=1)
         Index Cond: (book_ref = '000068'::bpchar)
   ->  Index Scan using bookings_2017_7_book_ref_idx on bookings_2017_7 bookings_partitioned_2  (cost=0.42..8.44 rows=1 width=21) (actual time=0.007..0.008 rows=0 loops=1)
         Index Cond: (book_ref = '000068'::bpchar)
   ->  Index Scan using bookings_2017_8_book_ref_idx on bookings_2017_8 bookings_partitioned_3  (cost=0.29..8.31 rows=1 width=21) (actual time=0.008..0.009 rows=1 loops=1)
         Index Cond: (book_ref = '000068'::bpchar)
 Planning Time: 0.096 ms
 Execution Time: 0.053 ms
(9 rows)
```
Поиск по `book_ref` стал на два порядка быстрее.


## Тестирование решения

 - Протестируйте секционирование, выполняя несколько запросов к секционированной таблице.
```commandline
SELECT * FROM bookings_partitioned WHERE book_ref = '000068';
```
```commandline
 book_ref |       book_date        | total_amount 
----------+------------------------+--------------
 000068   | 2017-08-15 11:27:00+00 |     18100.00
```

 - Проверьте, что операции вставки, обновления и удаления работают корректно.
```commandline
INSERT INTO bookings_partitioned (book_ref, book_date, total_amount) VALUES ('999999', '2017-08-15 11:27:00+00'::date, 999 );
UPDATE bookings_partitioned SET total_amount = 888 WHERE book_ref = '999999';
SELECT * FROM bookings_partitioned WHERE book_ref = '999999';
```
```commandline
 book_ref |       book_date        | total_amount 
----------+------------------------+--------------
 999999   | 2017-08-15 00:00:00+00 |       888.00
```
<hr>

### Выводы

Секционирование позволяет размещать данные в нескольких файлах, обращаясь к ним как к единой таблице.
Для ускорения запросов:
 - возможно разместить файлы на разных по скорости дисках
 - обойти ограничения фаловой системы на размер одного файла
 - строить индексы на партиции в зависимости от частоты\тяжести запросов
 - ускорить работу с нужными данными (сканируются только подходящие партиции)
 - ускорить работу с ненужными данными (drop старых таблиц)

