# HW 09
 <hr>

### Подготовка
Сделаем и заполним таблицу тестовыми данными:
```postgresql
DROP TABLE IF EXISTS products;

CREATE TABLE products(
    product_id   integer,
    brand        char(10),
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
    array_to_string(ARRAY(SELECT chr((97 + round(random() * 25)) :: integer) FROM generate_series(1,round(random_data.rand2 * 9 + 1) :: integer)), ''),
    case when random_data.num % 2 = 0 then 'М' else 'Ж' end,
    (random_data.rand2 * 100)::integer,
    random_data.rand3 < 0.01
    FROM random_data
    ORDER BY random();
```

```postgresql
SELECT * FROM products LIMIT 5;
```
```commandline
 product_id |   brand    | gender | price | is_available 
------------+------------+--------+-------+--------------
      67121 | ofbmxftr   | Ж      |    78 | f
      17302 | orppj      | М      |    45 | f
      12719 | hnlmt      | Ж      |    46 | f
      88799 | lvqthf     | Ж      |    55 | f
      39813 | wfe        | Ж      |    21 | f
(5 rows)
```

### Создать индекс к какой-либо из таблиц вашей БД

```postgresql
CREATE INDEX
    idx_products_product_id
    ON products(product_id);
```
```postgresql
ANALYZE products;
```

### Прислать текстом результат команды explain, в которой используется данный индекс
```postgresql
EXPLAIN
SELECT * FROM products
    WHERE product_id < 100;
```
```commandline
                                      QUERY PLAN                                       
---------------------------------------------------------------------------------------
 Bitmap Heap Scan on products  (cost=5.06..279.12 rows=99 width=23)
   Recheck Cond: (product_id < 100)
   ->  Bitmap Index Scan on idx_products_product_id  (cost=0.00..5.04 rows=99 width=0)
         Index Cond: (product_id < 100)
(4 rows)
```
<details>
  <summary>Как читать план запроса</summary>

- сначала выполняется Bitmap Index Scan, и из индекса берутся адреса строк для условия `product_id = 1`
- затем выполняется Bitmap Heap Scan, и из таблицы выбираются нужные строки с результатом запроса
- Bitmap (битовая карта) нужен для сортировки, чтобы последовательно прочитать дисковые страницы
- Recheck Cond нужен для поиска конкретных записей на дисковых страницах
</details>

### Что влияет на выбор индекса планировщиком?
<details><summary></summary>

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
</details>

### Реализовать индекс для полнотекстового поиска

##### GIN-индексы

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
```commandline
   title    |                         metadata                         |                   contents                   
------------+----------------------------------------------------------+----------------------------------------------
 Document 1 | {"tags": ["legal", "real estate"], "author": "John"}     | This is a legal document about real estate.
 Document 2 | {"tags": ["finance", "legal"], "author": "Jane"}         | Financial statements should be verified.
 Document 3 | {"tags": ["health", "nutrition"], "author": "Paul"}      | Regular exercise promotes better health.
 Document 4 | {"tags": ["travel", "adventure"], "author": "Alice"}     | Mountaineering requires careful preparation.
 Document 5 | {"tags": ["legal", "contracts"], "author": "Bob"}        | Contracts are binding legal documents.
 Document 6 | {"tags": ["legal", "family law"], "author": "Eve"}       | Family law addresses diverse issues.
 Document 7 | {"tags": ["technology", "innovation"], "author": "John"} | Tech innovations are changing the world.
(7 rows)
```

Пробуем наивный полнотекстовый поиск:

```postgresql
SELECT * FROM documents
    WHERE contents like '%document%';
```
```commandline
   title    |                       metadata                       |                  contents                   
------------+------------------------------------------------------+---------------------------------------------
 Document 1 | {"tags": ["legal", "real estate"], "author": "John"} | This is a legal document about real estate.
 Document 5 | {"tags": ["legal", "contracts"], "author": "Bob"}    | Contracts are binding legal documents.
(2 rows)
```

```postgresql
EXPLAIN
SELECT * FROM documents
    WHERE contents like '%document%';
```
```commandline
                         QUERY PLAN                         
------------------------------------------------------------
 Seq Scan on documents  (cost=0.00..14.25 rows=1 width=210)
   Filter: (contents ~~ '%document%'::text)
(2 rows)
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
```commandline
   title    |                       metadata                       |                  contents                   
------------+------------------------------------------------------+---------------------------------------------
 Document 1 | {"tags": ["legal", "real estate"], "author": "John"} | This is a legal document about real estate.
 Document 5 | {"tags": ["legal", "contracts"], "author": "Bob"}    | Contracts are binding legal documents.
(2 rows)
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
```commandline
                                          QUERY PLAN                                          
----------------------------------------------------------------------------------------------
 Bitmap Heap Scan on documents  (cost=8.00..12.26 rows=1 width=210)
   Recheck Cond: (to_tsvector('english'::regconfig, contents) @@ '''document'''::tsquery)
   ->  Bitmap Index Scan on idx_documents_contents  (cost=0.00..8.00 rows=1 width=0)
         Index Cond: (to_tsvector('english'::regconfig, contents) @@ '''document'''::tsquery)
(4 rows)
```

```postgresql
SET enable_seqscan = ON;
```

### Реализовать индекс на часть таблицы или индекс на поле с функцией

[https://postgrespro.ru/docs/postgresql/16/indexes-partial](https://postgrespro.ru/docs/postgresql/16/indexes-partial)

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
```commandline
                                           QUERY PLAN                                           
------------------------------------------------------------------------------------------------
 Index Scan using idx_products_is_available on products  (cost=0.29..130.38 rows=1010 width=23)
   Index Cond: (is_available = true)
(2 rows)
```

```postgresql
EXPLAIN
SELECT * FROM products
    WHERE is_available = false;
```
```commandline
                                          QUERY PLAN                                           
-----------------------------------------------------------------------------------------------
 Bitmap Heap Scan on products  (cost=1115.46..2841.36 rows=98990 width=23)
   Filter: (NOT is_available)
   ->  Bitmap Index Scan on idx_products_is_available  (cost=0.00..1090.72 rows=98990 width=0)
         Index Cond: (is_available = false)
(4 rows)
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

Насколько большой индекс у нас получился ранее для `is_available`?

```postgresql
SELECT relpages
    FROM pg_class
    WHERE relname = 'idx_products_is_available';
```
```commandline
 relpages 
----------
       87
(1 row)
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
```commandline
                                             QUERY PLAN                                              
-----------------------------------------------------------------------------------------------------
 Index Scan using idx_products_is_available_true on products  (cost=0.15..131.71 rows=1010 width=23)
(1 row)
```

А насколько большой индекс у нас получился теперь?

```postgresql
SELECT relpages
    FROM pg_class
    WHERE relname = 'idx_products_is_available_true';
```
```commandline
 relpages 
----------
        2
(1 row)
```

### Создать индекс на несколько полей

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
    WHERE product_id <= 100000
    AND brand = 'wfe';
```
```commandline
                                          QUERY PLAN                                           
-----------------------------------------------------------------------------------------------
 Index Scan using idx_products_brand_product_id on products  (cost=0.42..8.44 rows=1 width=23)
   Index Cond: ((brand = 'wfe'::bpchar) AND (product_id <= 100000))
(2 rows)
```
```postgresql
EXPLAIN                         
SELECT * FROM products
    WHERE product_id = 39813
    AND brand <= 'wfe';
```
```commandline
QUERY PLAN                                        
-----------------------------------------------------------------------------------------
 Index Scan using idx_products_product_id on products  (cost=0.29..8.31 rows=1 width=23)
   Index Cond: (product_id = 39813)
   Filter: (brand <= 'wfe'::bpchar)
(3 rows)
```

 - В зависимости от запроса могут использоваться разные индексы (выбирается наиболее подходящий). 
 - А может не использоваться ни один, если последовательное сканирование окажется эффективнее.
 - Решение принимает планировщик, основываясь на выделенном времени на прогноз - чем больше времени анализирует тем точнее результат.


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