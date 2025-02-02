# Виды индексов

## Подготовка к занятию

```postgresql
DROP EXTENSION IF EXISTS btree_gist;
DROP DATABASE IF EXISTS otus_dba_indexes;
CREATE DATABASE otus_dba_indexes;
```

```postgresql
\c otus_dba_indexes
```

```postgresql
\pset null <NULL>
```

```postgresql
SET timezone TO "Europe/Moscow";
```

## Основы индексации

### Исходные условия

```
 offer_id |  name  | area
----------+--------+------
        1 | Кв. 1  |   36      ┐
        2 | Кв. 2  |   41      |  
      ... | ...    |  ...      |  Дисковая страница 1 (10 записей)
        9 | Кв. 9  |  110      |
       10 | Кв. 10 |   79      ┘
       11 | Кв. 11 |   36      ┐
       12 | Кв. 12 |   90      |  
      ... | ...    |  ...      |  Дисковая страница 2 (10 записей)
       19 | Кв. 19 |   38      |
       20 | Кв. 20 |   40      ┘
      ... | ...    |  ...
      ... | ...    |  ...
      ... | ...    |  ...
    99991 | Кв. N1 |   36      ┐
    99992 | Кв. N2 |  148      |  
      ... | ...    |  ...      |  Дисковая страница 10,000 (10 записей)
    99999 | Кв. N9 |   60      |
   100000 | Кв. NN |   90      ┘
```

## Базовые индексы

### Таблица товаров

```postgresql
DROP TABLE IF EXISTS products;

CREATE TABLE products(
    product_id   integer,
    brand        char(1),
    gender       char(1),
    price        integer,
    is_available boolean
);
```

```
 product_id |  brand  | gender | price | is_available
------------+---------+--------+-------+--------------
       5057 | Zara    | Ж      |    27 | f
      92669 | Bershka | Ж      |    35 | f
      52477 | H&M     | Ж      |    88 | f
      35864 | Zara    | М      |    41 | t
        ... | ...     | ...    |   ... | ...
```

```postgresql
WITH random_data AS (
    SELECT
    num,
    random() AS rand1,
    random() AS rand2,
    random() AS rand3
    FROM generate_series(1, 100000) AS s(num)
)
INSERT INTO products
    (product_id, brand, gender, price, is_available)
SELECT
    random_data.num,
    chr((32 + random_data.rand1 * 94)::integer),
    case when random_data.num % 2 = 0 then 'М' else 'Ж' end,
    (random_data.rand2 * 100)::integer,
    random_data.rand3 < 0.01
    FROM random_data
    ORDER BY random();
```

```postgresql
SELECT * FROM products;
```

### Простые индексы

Смотрим план запроса для выборки по равенству:

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id = 1;
```

Смотрим план запроса для выборки по диапазону:

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id < 100;
```

В обоих случаях мы увидели последовательное сканирование таблицы:

```
                          QUERY PLAN
--------------------------------------------------------------
 Seq Scan on products  (cost=0.00..1863.23 rows=490 width=25)
   Filter: (product_id = 1)
```

Добавляем индекс B-Tree на это поле:

```postgresql
CREATE INDEX
    idx_products_product_id
    ON products(product_id);
```

```postgresql
ANALYZE products;
```

Проверяем результат:

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id = 1;
```

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id < 100;
```

План запроса читается снизу вверх:

- сначала выполняется Bitmap Index Scan, и из индекса берутся адреса строк для условия `product_id = 1`
- затем выполняется Bitmap Heap Scan, и из таблицы выбираются нужные строки с результатом запроса
- Bitmap (битовая карта) нужен для сортировки, чтобы последовательно прочитать дисковые страницы
- Recheck Cond нужен для поиска конкретных записей на дисковых страницах

```
                               QUERY PLAN
-------------------------------------------------------------------------
 Bitmap Heap Scan on products  (cost=12.17..646.51 rows=500 width=25)
   Recheck Cond: (product_id = 1)
   ->  Bitmap Index Scan on idx...  (cost=0.00..12.04 rows=500 width=0)
         Index Cond: (product_id = 1)
```

Добавляем индекс на поле с брендом:

```postgresql
CREATE INDEX
    idx_products_brand
    ON products(brand);
```

```postgresql
ANALYZE products;
```

Смотрим план запроса с условиями по двум полям:

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id <= 100
    AND brand = 'a';
```

В данном случае планировщик посчитал, что ему выгоднее объединить два индекса, чем взять один из них:

```
                             QUERY PLAN
-----------------------------------------------------------------------------
 Bitmap Heap Scan on products  (cost=16.49..20.51 rows=1 width=14)
   Recheck Cond: ((product_id <= 100) AND (brand = 'a'::bpchar))
   ->  BitmapAnd  (cost=16.49..16.49 rows=1 width=0)
         ->  Bitmap Index Scan on idx...  (cost=0.00..5.03 rows=98 width=0)
               Index Cond: (product_id <= 100)
         ->  Bitmap Index Scan on idx...  (cost=0.00..11.21 rows=923 width=0)
               Index Cond: (brand = 'a'::bpchar)
```

### Что влияет на выбор индекса планировщиком?

**Количество уникальных значений**

Результат `−1` означает, что все значения в столбце уникальны:

```postgresql
SELECT
    s.n_distinct
    FROM pg_stats s
    WHERE s.tablename = 'products'
    AND s.attname = 'product_id';
```

```postgresql
SELECT
    s.n_distinct
    FROM pg_stats s
    WHERE s.tablename = 'products'
    AND s.attname = 'brand';
```

```postgresql
SELECT
    s.n_distinct
    FROM pg_stats s
    WHERE s.tablename = 'products'
    AND s.attname = 'gender';
```

```postgresql
SELECT
    s.n_distinct
    FROM pg_stats s
    WHERE s.tablename = 'products'
    AND s.attname = 'is_available';
```

**Ожидаемый объём результата**

Сравниваем два диапазонных запроса:

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id < 100;
```

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id < 40000;
```

**Реальное распределение значений**

Смотрим план запроса для булевого поля:

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE is_available = true;
```

Создаём индекс:

```postgresql
CREATE INDEX
    idx_products_is_available
    ON products(is_available);
```

```postgresql
ANALYZE products;
```

Проверяем результат:

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE is_available = true;
```

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE is_available = false;
```

Почему так получилось? Результат может быть связан с тем, какие данные хранятся в таблице.

```postgresql
SELECT is_available, count(*) AS count
    FROM products
    GROUP BY is_available;
```

Смотрим статистику:

```postgresql
SELECT
    most_common_vals AS mcv,
    left(most_common_freqs::text,60) || '...' AS mcf
    FROM pg_stats
    WHERE tablename = 'products'
    AND attname = 'is_available' \gx
```

**Корреляция**

Если значения хранятся строго по возрастанию, корреляция будет близка к единице; если по убыванию — к минус единице. Чем более хаотично расположены данные на диске, тем ближе значение к нулю.

```postgresql
SELECT attname, correlation
    FROM pg_stats
    WHERE tablename = 'products';
```

Смотрим пример с автоинкрементным полем:

```postgresql
DROP TABLE IF EXISTS autoincrement;

CREATE TABLE autoincrement(
    id          serial,
    negative_id integer
);
```

```postgresql
WITH random_data AS (
    SELECT
        num
        FROM generate_series(1, 100000) AS s(num)
)
INSERT INTO autoincrement
    (negative_id)
SELECT
    random_data.num * -1
    FROM random_data;
```

```postgresql
ANALYZE autoincrement;
```

```postgresql
SELECT attname, correlation
    FROM pg_stats
    WHERE tablename = 'autoincrement';
```

### Составные индексы

Создаём составные индексы:

```postgresql
CREATE INDEX
    idx_products_product_id_brand
    ON products(product_id, brand);
```

```postgresql
CREATE INDEX
    idx_products_brand_product_id
    ON products(brand, product_id);
```

```postgresql
ANALYZE products;
```

Сравниваем планы запросов с использованием составного индекса:

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id <= 100
    AND brand = 'a';
```

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id = 100
    AND brand <= 'a';
```

### Частичные индексы

Насколько большой индекс у нас получился ранее для `is_available`?

```postgresql
SELECT relpages
    FROM pg_class
    WHERE relname = 'idx_products_is_available';
```

Создаём частичный индекс для булевого поля:

```postgresql
DROP INDEX idx_products_is_available;
```

```postgresql
CREATE INDEX idx_products_is_available_true
    ON products(is_available)
    WHERE is_available = true;
```

```postgresql
ANALYZE products;
```

Проверяем результат:

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE is_available = true;
```

А насколько большой индекс у нас получился теперь?

```postgresql
SELECT relpages
    FROM pg_class
    WHERE relname = 'idx_products_is_available_true';
```

### Покрывающие индексы

Анализируем запрос:

```postgresql
EXPLAIN
SELECT product_id, gender FROM products
    WHERE product_id <= 100;
```

Мы часто ищем комбинацию (`product_id`, `gender`), но за `gender` приходится каждый раз "ходить" в основную таблицу. Попробуем добавить `gender` прямо внутрь нашего индекса:

```postgresql
CREATE INDEX
    idx_products_product_id_with_gender
    ON products(product_id)
    INCLUDE(gender);
```

```postgresql
ANALYZE products;
```

Проверяем результат:

```postgresql
EXPLAIN
SELECT product_id, gender FROM products
    WHERE product_id <= 100;
```

### Функциональные индексы

Типичный сценарий — когда при поиске сначала выполняются какие-то вычисления над данными:

```postgresql
SELECT
    product_id, price, (price::numeric / 6) AS price_mxn
    FROM products
    WHERE (price::numeric / 6) > 15.5;
```

Индекс на price здесь не поможет; нужен вспомогательный функциональный индекс.

```postgresql
CREATE INDEX
    func_idx_products_price_mxn
    ON products ((price::numeric / 6));
```

```postgresql
SELECT
    product_id, price, (price::numeric / 6) AS price_mxn
    FROM products
    WHERE (price::numeric / 6) > 15.5;
```

```postgresql
EXPLAIN
SELECT
    product_id, price, (price::numeric / 6) AS price_mxn
    FROM products
    WHERE (price::numeric / 6) > 15.5;
```

Другой пример — работа с фрагментами строк. Пример с КЛАДР:

```postgresql
DROP TABLE IF EXISTS cities;

CREATE TABLE cities (
    code CHAR(13) PRIMARY KEY,
    name VARCHAR(255) NOT NULL
);
```

```
     code      |       name
---------------+-----------------
 3700000056790 | Кемерово
 3700000056790 | Королев
 3700000056790 | Красногорск
 3700000056790 | Краснодар
 3700000056790 | Мытищи
 3700000056790 | Нижний Новгород
 3700000056790 | Оренбург
 ...           | ...
```

```postgresql
WITH random_data AS (
    SELECT
    num,
    random() AS rand1,
    random() AS rand2,
    random() AS rand3
    FROM generate_series(1, 100000) AS s(num)
)
INSERT INTO cities
    (code, name)
SELECT
    concat(
        (random_data.rand1 * 10)::integer % 10,
        (random_data.rand2 * 10)::integer % 10,
        lpad(random_data.num::text, 11, '0')
    ),
    chr((32 + random_data.rand3 * 94)::integer)
    FROM random_data
    ORDER BY random();
```

```postgresql
SELECT * FROM cities;
```

Делаем выборку по коду региона:

```postgresql
SELECT * FROM cities
    WHERE SUBSTRING(code, 1, 2) = '50';
```

```postgresql
EXPLAIN
SELECT * FROM cities
    WHERE SUBSTRING(code, 1, 2) = '50';
```

Создаём функциональный индекс:

```postgresql
CREATE INDEX
    func_idx_cities_region
    ON cities ((SUBSTRING(code, 1, 2)));
```

```postgresql
ANALYZE cities;
```

Проверяем результат:

```postgresql
EXPLAIN
SELECT * FROM cities
    WHERE SUBSTRING(code, 1, 2) = '50';
```

## GIN-индексы

Создаём и заполняем таблицу с документами:

```postgresql
DROP TABLE IF EXISTS documents;

CREATE TABLE documents (
    title    varchar(64),
    metadata jsonb,
    contents text
);
```

```postgresql
INSERT INTO documents
    (title, metadata, contents)
VALUES
    ( 'Document 1',
      '{"author": "John",  "tags": ["legal", "real estate"]}',
      'This is a legal document about real estate.' ),
    ( 'Document 2',
      '{"author": "Jane",  "tags": ["finance", "legal"]}',
      'Financial statements should be verified.' ),
    ( 'Document 3',
      '{"author": "Paul",  "tags": ["health", "nutrition"]}',
      'Regular exercise promotes better health.' ),
    ( 'Document 4',
      '{"author": "Alice", "tags": ["travel", "adventure"]}',
      'Mountaineering requires careful preparation.' ),
    ( 'Document 5',
      '{"author": "Bob",   "tags": ["legal", "contracts"]}',
      'Contracts are binding legal documents.' ),
    ( 'Document 6',
       '{"author": "Eve",  "tags": ["legal", "family law"]}',
       'Family law addresses diverse issues.' ),
    ( 'Document 7',
      '{"author": "John",  "tags": ["technology", "innovation"]}',
      'Tech innovations are changing the world.' );
```

```postgresql
SELECT * FROM documents;
```

Ищем все документы, созданные автором по имени Джон:

```postgresql
SELECT * FROM documents
    WHERE metadata @> '{"author": "John"}';
```

Создаём GIN-индекс на JSON-объекты:

```postgresql
CREATE INDEX
    idx_documents_metadata
    ON documents
    USING GIN (metadata);
```

Проверяем результат (с отключенным последовательным сканированием):

```postgresql
SET enable_seqscan = OFF;
```

```postgresql
EXPLAIN
SELECT * FROM documents
    WHERE metadata @> '{"author": "John"}';
```

Пробуем найти документы по тегам:

```postgresql
SELECT * FROM documents
    WHERE metadata->'tags' ? 'legal';
```

```postgresql
EXPLAIN
SELECT * FROM documents
    WHERE metadata->'tags' ? 'legal';
```

Добавляем индекс на теги:

```postgresql
CREATE INDEX
    idx_documents_metadata_tags
    ON documents
    USING gin((metadata->'tags'));
```

Проверяем результат:

```postgresql
EXPLAIN
SELECT * FROM documents
    WHERE metadata->'tags' ? 'legal';
```

```postgresql
SET enable_seqscan = ON;
```

Пробуем наивный полнотекстовый поиск:

```postgresql
SELECT * FROM documents
    WHERE contents like '%document%';
```

```postgresql
EXPLAIN
SELECT * FROM documents
    WHERE contents like '%document%';
```

Добавляем GIN-индекс на текст документа:

```postgresql
CREATE INDEX
    idx_documents_contents
    ON documents
    USING GIN(to_tsvector('english', contents));
```

```postgresql
SELECT * FROM documents
    WHERE to_tsvector('english', contents) @@ 'document';
```

Проверяем результат (с отключенным последовательным сканированием):

```postgresql
SET enable_seqscan = OFF;
```

```postgresql
EXPLAIN
SELECT * FROM documents
    WHERE to_tsvector('english', contents) @@ 'document';
```

```postgresql
SET enable_seqscan = ON;
```

## Индексы GiST

### Геометрические типы

```postgresql
DROP TABLE IF EXISTS graph;

CREATE TABLE graph (
  name char(1),
  point point
);
```

### Пример графика

```postgresql
INSERT INTO graph
  (name, point)
  VALUES
  ('A', point '(1, 1)'),
  ('B', point '(2, 4)'),
  ('C', point '(3, 9)'),
  ('X', point '(-1, 1)'),
  ('Y', point '(-2, 4)'),
  ('Z', point '(-3, 9)');
```

```postgresql
SELECT * FROM graph;
```

Ищем точки, входящие в прямоугольник:

```postgresql
SELECT * FROM graph 
  WHERE point <@ box '(0,0),(100,100)';
```

Насколько быстро работает такой запрос? Смотрим на план запроса:

```postgresql
EXPLAIN ANALYZE
SELECT * FROM graph 
  WHERE point <@ box '(0,0),(100,100)';
```

### Индекс GiST

```postgresql
CREATE INDEX ON graph USING gist(point);
```

```postgresql
SET enable_seqscan = off;
```

```postgresql
EXPLAIN ANALYZE
SELECT * FROM graph 
  WHERE point <@ box '(0,0),(100,100)';
```

```postgresql
SET enable_seqscan = on;
```

### Диапазонные типы

```postgresql
DROP TABLE IF EXISTS webinars;

CREATE TABLE webinars (
  webinar_id        serial PRIMARY KEY,
  created_at        timestamptz NOT NULL,
  teacher_id        int NOT NULL,
  expected_students int NOT NULL,
  schedule          tstzrange NOT NULL
);
```

```postgresql
INSERT INTO webinars
  (created_at, teacher_id, expected_students, schedule)
  VALUES
  ( '2024-06-01 15:00:08+03',
     1,
     24,
    '[2024-06-10 20:00:00+03, 2024-06-10 21:30:00+03)'
  ),
  ( '2024-06-01 15:30:12+03',
     2,
     15,
    '[2024-06-10 20:00:00+03, 2024-06-10 21:30:00+03)'
  ),
  ( '2024-06-01 15:48:00+03',
     2,
     10,
    '[2024-06-11 20:00:00+03, 2024-06-11 21:30:00+03)'
  ),
  ( '2024-06-02 09:25:15+03',
     1,
     5,
    '[2024-06-14 18:00:00+03, 2024-06-14 21:30:00+03)'
  ),
  ( '2024-06-02 12:34:02+03',
     2,
     12,
    '[2024-06-14 20:00:00+03, 2024-06-14 21:30:00+03)'
  );
```

### Визуализация расписания

```postgresql
SELECT * FROM webinars;
```

Сценарий 1. Мы знаем конкретное значение и хотим найти диапазоны, в которые оно входит. Пример: у нас есть конкретное значение "14 июня 20:15". Нам интересно, какие вебинары будут идти в этот момент времени. (оператор вхождения @>)

```postgresql
SELECT * FROM webinars
  WHERE schedule @> '2024-06-14 20:15:00+3'::timestamptz;
```

Сценарий 2. Мы знаем конкретный диапазон и хотим найти значения, которые в него попадают. Запрос: какие вебинары были введены в систему утром 2 июня?

```postgresql
SELECT tstzrange(
  '2024-06-02 08:00:00+03',
  '2024-06-02 12:00:00+03',
  '[)'
);
```

Ищем записи, где этот диапазон включает в себя дату ввода в систему:

```postgresql
SELECT * FROM webinars
  WHERE tstzrange(
    '2024-06-02 08:00:00+03',
    '2024-06-02 12:00:00+03',
    '[)'
  ) @> created_at;
```

Для лучшей читаемости оператор можно "развернуть". Ищем записи, где дата ввода в систему входит в этот диапазон:

```postgresql
SELECT * FROM webinars
  WHERE created_at <@ tstzrange(
    '2024-06-02 08:00:00+03',
    '2024-06-02 12:00:00+03',
    '[)'
  );
```

Можно делать гибридные запросы. Запрос: какие вебинары проводились 10 июня? (оператор пересечения диапазонов &&)

```postgresql
SELECT * FROM webinars
  WHERE schedule && tstzrange(
    '2024-06-10+03',
    '2024-06-11+03',
    '[)'
  );
```

При этом ищется именно пересечение, а не полное вхождение, т.е. будет работать и вот так:

```postgresql
SELECT * FROM webinars
  WHERE schedule && tstzrange(
    '2024-06-10 21:00+03',
    '2024-06-11+03',
    '[)'
  );
```

### Визуализация расписания (индекс)

```postgresql
CREATE INDEX ON webinars USING gist(schedule);
```

```postgresql
SET enable_seqscan = off;
```

```postgresql
EXPLAIN ANALYZE
SELECT * FROM webinars
  WHERE schedule && tstzrange(
    '2024-06-10+03',
    '2024-06-12+03',
    '[)'
  );
```

Ищем все вебинары, прошедшие 10-11 июня, на которых ожидалось меньше 15 студентов.

```postgresql
SELECT * FROM webinars
  WHERE schedule && tstzrange('2024-06-10+03', '2024-06-12+03', '[)')
  AND expected_students < 15;
```

Смотрим план запроса:

```postgresql
EXPLAIN ANALYZE
SELECT * FROM webinars
  WHERE schedule && tstzrange('2024-06-10+03', '2024-06-12+03', '[)')
  AND expected_students < 15;
```

В результате видим, что над строками выполняется Filter.

### Визуализация расписания (со студентами)

Попробуем добавить студентов в индекс:

```postgresql
CREATE INDEX ON webinars USING gist(expected_students, schedule);
```

```postgresql
CREATE EXTENSION btree_gist;
```

```postgresql
CREATE INDEX ON webinars USING gist(expected_students, schedule);
```

```postgresql
EXPLAIN ANALYZE
SELECT * FROM webinars
  WHERE schedule && tstzrange('2024-06-10+03', '2024-06-12+03', '[)')
  AND expected_students < 20;
```

Видим, что в плане запроса больше нет фильтраций. Такие запросы выполняются очень быстро.

```postgresql
SET enable_seqscan = on;
```

### Диапазонные типы: ограничения

```postgresql
ALTER TABLE webinars
  ADD CONSTRAINT unique_schedule_per_teacher
  EXCLUDE USING gist (
    teacher_id WITH =,
    schedule   WITH &&
  );
```

Пробуем вставку на 11 июня для преподавателя #2 (у него уже есть занятие с 20:00)

```postgresql
INSERT INTO webinars
  (created_at, teacher_id, expected_students, schedule)
  VALUES
  ( '2024-06-03 11:20:08+03',
     2,
     18,
    '[2024-06-11 19:00:00+03, 2024-06-11 20:30:00+03)'
  );
```

Передаём это занятие преподавателю #1 (у него в этот день нет занятий) и пробуем вставку:

```postgresql
INSERT INTO webinars
  (created_at, teacher_id, expected_students, schedule)
  VALUES
  ( '2024-06-03 11:20:08+03',
     1,
     18,
    '[2024-06-11 19:00:00+03, 2024-06-11 20:30:00+03)'
  );
```

```postgresql
SELECT * FROM webinars;
```

## Итоги

### Статистика индексов

```postgresql
SELECT
    TABLE_NAME,
    pg_size_pretty(table_size) AS table_size,
    pg_size_pretty(indexes_size) AS indexes_size,
    pg_size_pretty(total_size) AS total_size
    FROM (
        SELECT
        TABLE_NAME,
        pg_table_size(TABLE_NAME) AS table_size,
        pg_indexes_size(TABLE_NAME) AS indexes_size,
        pg_total_relation_size(TABLE_NAME) AS total_size
        FROM (
            SELECT ('"' || table_schema || '"."' || TABLE_NAME || '"')
            AS TABLE_NAME
            FROM information_schema.tables
        ) AS all_tables
        ORDER BY total_size DESC
    ) AS pretty_sizes;
```

### Неиспользуемые индексы

```postgresql
SELECT
    s.schemaname,
    s.relname AS tablename,
    s.indexrelname AS indexname,
    pg_size_pretty(pg_relation_size(s.indexrelid)) AS index_size,
    s.idx_scan
    FROM pg_catalog.pg_stat_user_indexes s
    JOIN pg_catalog.pg_index i ON s.indexrelid = i.indexrelid
    WHERE s.idx_scan < 10    -- has never been scanned
    AND 0 <>ALL (i.indkey)   -- no index column is an expression
    AND NOT i.indisunique    -- is not a UNIQUE index
    AND NOT EXISTS           -- does not enforce a constraint
    (
        SELECT 1
        FROM pg_catalog.pg_constraint c
        WHERE c.conindid = s.indexrelid
    )
    ORDER BY pg_relation_size(s.indexrelid) DESC;
```

