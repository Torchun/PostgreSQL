# HW 11. Триггеры, поддержка заполнения витрин
 <hr>

### Подготовка
Сделаем БД:
```commandline
CREATE DATABASE hw11;
\c hw11
```
В БД создана структура, описывающая товары (таблица goods) и продажи (таблица sales).

Есть запрос для генерации отчета – сумма продаж по каждому товару.

БД была денормализована, создана таблица (витрина), структура которой повторяет структуру отчета.

Создать триггер на таблице продаж, для поддержки данных в витрине в актуальном состоянии (вычисляющий при каждой продаже сумму и записывающий её в витрину)

Подсказка: не забыть, что кроме INSERT есть еще UPDATE и DELETE

```postgresql
-- ДЗ тема: триггеры, поддержка заполнения витрин

DROP SCHEMA IF EXISTS pract_functions CASCADE;
CREATE SCHEMA pract_functions;

SET search_path = pract_functions, publ

-- товары:
CREATE TABLE goods
(
    goods_id    integer PRIMARY KEY,
    good_name   varchar(63) NOT NULL,
    good_price  numeric(12, 2) NOT NULL CHECK (good_price > 0.0)
);
INSERT INTO goods (goods_id, good_name, good_price)
VALUES (1, 'Спички хозайственные', .50), (2, 'Автомобиль Ferrari FXX K', 185000000.01);

-- Продажи
CREATE TABLE sales
(
    sales_id    integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    good_id     integer REFERENCES goods (goods_id),
    sales_time  timestamp with time zone DEFAULT now(),
    sales_qty   integer CHECK (sales_qty > 0)
);

INSERT INTO sales (good_id, sales_qty) VALUES (1, 10), (1, 1), (1, 120), (2, 1);

-- отчет:
SELECT G.good_name, sum(G.good_price * S.sales_qty)
FROM goods G
INNER JOIN sales S ON S.good_id = G.goods_id
GROUP BY G.good_name;

-- с увеличением объёма данных отчет стал создаваться медленно
-- Принято решение денормализовать БД, создать таблицу
CREATE TABLE good_sum_mart
(
	good_name   varchar(63) NOT NULL,
	sum_sale	numeric(16, 2)NOT NULL
);

-- Создать триггер (на таблице sales) для поддержки.
-- Подсказка: не забыть, что кроме INSERT есть еще UPDATE и DELETE

-- Чем такая схема (витрина+триггер) предпочтительнее отчета, создаваемого "по требованию" (кроме производительности)?
-- Подсказка: В реальной жизни возможны изменения цен.

```

Делаем функцию:
```commandline
CREATE OR REPLACE FUNCTION calculate_sales()
RETURNS trigger
AS
$$
DECLARE
  goods_row record;
  new_row   record;
begin

  -- https://postgrespro.ru/docs/postgrespro/9.6/plpgsql-trigger#plpgsql-dml-trigger
  CASE TG_OP
    WHEN 'DELETE'
      THEN goods_row = OLD;
    WHEN 'UPDATE'
      THEN goods_row = NEW;
    WHEN 'INSERT'
      THEN goods_row = NEW;
  END CASE;
      
  SELECT G.good_name AS good_name, coalesce(sum(G.good_price * S.sales_qty), 0) AS sum_sale INTO new_row
  FROM pract_functions.goods G
  LEFT JOIN pract_functions.sales S ON S.good_id = G.goods_id
  WHERE G.goods_id = goods_row.good_id
  GROUP BY G.good_name;

  -- https://stackoverflow.com/a/11892796
  IF EXISTS (SELECT 1 FROM pract_functions.good_sum_mart WHERE good_name = new_row.good_name) THEN
    IF (new_row.sum_sale = 0) THEN 
      DELETE from pract_functions.good_sum_mart WHERE good_name = new_row.good_name;
    ELSE
      UPDATE pract_functions.good_sum_mart SET sum_sale = new_row.sum_sale WHERE good_name = new_row.good_name;
    END IF;
  ELSE
    INSERT INTO pract_functions.good_sum_mart (good_name, sum_sale) VALUES (new_row.good_name, new_row.sum_sale);
  END IF;

  RETURN goods_row;
END;
$$ LANGUAGE plpgsql;
```
Проверяем наличие:
```commandline
\df
                                 List of functions
     Schema      |      Name       | Result data type | Argument data types | Type 
-----------------+-----------------+------------------+---------------------+------
 pract_functions | calculate_sales | trigger          |                     | func
(1 row)
```

Делаем триггер:
```commandline
CREATE TRIGGER trigger_sales_changed
AFTER INSERT OR UPDATE OR DELETE
ON pract_functions.sales
FOR EACH ROW
EXECUTE FUNCTION calculate_sales();
```
Проверяем наличие:
```commandline
SELECT * FROM pg_trigger WHERE tgname = 'trigger_sales_changed'; 

-[ RECORD 1 ]--+----------------------
oid            | 16663
tgrelid        | 16647
tgparentid     | 0
tgname         | trigger_sales_changed
tgfoid         | 16662
tgtype         | 29
tgenabled      | O
tgisinternal   | f
tgconstrrelid  | 0
tgconstrindid  | 0
tgconstraint   | 0
tgdeferrable   | f
tginitdeferred | f
tgnargs        | 0
tgattr         | 
tgargs         | \x
tgqual         | 
tgoldtable     | 
tgnewtable     | 
```

Текущие состояния таблицы и отчета:
```commandline
hw11=# SELECT * FROM pract_functions.sales;
 sales_id | good_id |          sales_time           | sales_qty 
----------+---------+-------------------------------+-----------
        1 |       1 | 2025-03-10 13:22:53.465434+00 |        10
        2 |       1 | 2025-03-10 13:22:53.465434+00 |         1
        3 |       1 | 2025-03-10 13:22:53.465434+00 |       120
        4 |       2 | 2025-03-10 13:22:53.465434+00 |         1
(4 rows)

hw11=# SELECT * FROM good_sum_mart;
 good_name | sum_sale 
-----------+----------
(0 rows)
```

### Проверяем срабатывание

Добавление строки:
```commandline
INSERT INTO pract_functions.sales (good_id,sales_time,sales_qty)
VALUES
(1,current_timestamp,10),
(2,current_timestamp,2);
```
```
SELECT * FROM pract_functions.sales;

 sales_id | good_id |          sales_time           | sales_qty 
----------+---------+-------------------------------+-----------
        1 |       1 | 2025-03-10 13:22:53.465434+00 |        10
        2 |       1 | 2025-03-10 13:22:53.465434+00 |         1
        3 |       1 | 2025-03-10 13:22:53.465434+00 |       120
        4 |       2 | 2025-03-10 13:22:53.465434+00 |         1
        5 |       1 | 2025-03-10 18:12:03.777818+00 |        10
        6 |       2 | 2025-03-10 18:12:03.777818+00 |         2
(6 rows)

hw11=# SELECT * FROM good_sum_mart;
        good_name         |   sum_sale   
--------------------------+--------------
 Спички хозайственные     |        70.50
 Автомобиль Ferrari FXX K | 555000000.03
(2 rows)
```

Изменение проданного количества:
```commandline
UPDATE pract_functions.sales SET sales_qty = 4 WHERE sales_id = 6;
```
```commandline
SELECT * FROM pract_functions.sales; SELECT * FROM good_sum_mart;
 sales_id | good_id |          sales_time           | sales_qty 
----------+---------+-------------------------------+-----------
        1 |       1 | 2025-03-10 13:22:53.465434+00 |        10
        2 |       1 | 2025-03-10 13:22:53.465434+00 |         1
        3 |       1 | 2025-03-10 13:22:53.465434+00 |       120
        4 |       2 | 2025-03-10 13:22:53.465434+00 |         1
        5 |       1 | 2025-03-10 18:12:03.777818+00 |        10
        6 |       2 | 2025-03-10 18:12:03.777818+00 |         4
(6 rows)

        good_name         |   sum_sale   
--------------------------+--------------
 Спички хозайственные     |        70.50
 Автомобиль Ferrari FXX K | 925000000.05
(2 rows)
```

Удаление:
```commandline
DELETE FROM pract_functions.sales WHERE sales_id = 6;
```
```commandline
SELECT * FROM pract_functions.sales; SELECT * FROM good_sum_mart;
 sales_id | good_id |          sales_time           | sales_qty 
----------+---------+-------------------------------+-----------
        1 |       1 | 2025-03-10 13:22:53.465434+00 |        10
        2 |       1 | 2025-03-10 13:22:53.465434+00 |         1
        3 |       1 | 2025-03-10 13:22:53.465434+00 |       120
        4 |       2 | 2025-03-10 13:22:53.465434+00 |         1
        5 |       1 | 2025-03-10 18:12:03.777818+00 |        10
(5 rows)

        good_name         |   sum_sale   
--------------------------+--------------
 Спички хозайственные     |        70.50
 Автомобиль Ferrari FXX K | 185000000.01
```

