
### Буферный кэш

```
-- Запрос текущего размера буфера shared_buffers
SELECT setting, unit FROM pg_settings WHERE name = 'shared_buffers';

-- Изменение размера shared_buffers на 200MB
ALTER SYSTEM SET shared_buffers = '200MB';

-- Показывает путь к файлу конфигурации сервера PostgreSQL
SHOW config_file;

-- Создание новой таблицы test
CREATE TABLE test(i int);

-- Вставка 100 значений в таблицу test с помощью функции generate_series
INSERT INTO test SELECT s.id FROM generate_series(1,100) AS s(id);

-- Выборка первых 10 записей из таблицы test
SELECT * FROM test LIMIT 10;

-- Создание расширения pg_buffercache для анализа использования буфера
CREATE EXTENSION pg_buffercache;

-- Создание представления pg_buffercache_v для удобного просмотра содержимого буфера
CREATE VIEW pg_buffercache_v AS
SELECT bufferid,
       (SELECT c.relname FROM pg_class c WHERE pg_relation_filenode(c.oid) = b.relfilenode) relname,
       CASE relforknumber
           WHEN 0 THEN 'main'
           WHEN 1 THEN 'fsm'
           WHEN 2 THEN 'vm'
       END relfork,
       relblocknumber,
       isdirty,
       usagecount
FROM pg_buffercache b
WHERE b.relDATABASE IN (0, (SELECT oid FROM pg_DATABASE WHERE datname = current_database()))
      AND b.usagecount IS NOT NULL;

-- Выборка записей из представления pg_buffercache_v для таблицы test
SELECT * FROM pg_buffercache_v WHERE relname='test';

-- Обновление значений в таблице test
UPDATE test SET i = 2 WHERE i = 1;

-- Повторная выборка из pg_buffercache_v после обновления данных в test
SELECT * FROM pg_buffercache_v WHERE relname='test';

-- Вставка новой записи в таблицу test
INSERT INTO test VALUES (2);

-- Сбор статистики по использованию блоков и буферов для всех таблиц
SELECT c.relname,
       count(*) blocks,
       round(100.0 * 8192 * count(*) / pg_TABLE_size(c.oid)) "% of rel",
       round(100.0 * 8192 * count(*) FILTER (WHERE b.usagecount > 3) / pg_TABLE_size(c.oid)) "% hot"
FROM pg_buffercache b
JOIN pg_class c ON pg_relation_filenode(c.oid) = b.relfilenode
WHERE b.relDATABASE IN (0, (SELECT oid FROM pg_DATABASE WHERE datname = current_database()))
      AND b.usagecount IS NOT NULL
GROUP BY c.relname, c.oid
ORDER BY 2 DESC
LIMIT 10;

-- Создание таблицы test_text для хранения строк
CREATE TABLE test_text(t text);

-- Заполнение таблицы test_text строками, используя generate_series
INSERT INTO test_text SELECT 'строка ' || s.id FROM generate_series(1,500) AS s(id);

-- Выборка первых 10 записей из таблицы test_text
SELECT * FROM test_text LIMIT 10;

-- Просмотр содержимого буфера для таблицы test_text
SELECT * FROM pg_buffercache_v WHERE relname='test_text';

SELECT * FROM pg_buffercache_v WHERE relname='test_text';
CREATE EXTENSION pg_prewarm;
SELECT pg_prewarm('test_text');
SELECT * FROM pg_buffercache_v WHERE relname='test_text';

```

### WAL

```
-- Удаляем таблицу wal, если она существует
DROP TABLE wal;

-- Создаем новую таблицу wal с одним столбцом id типа integer
CREATE TABLE wal(id integer);

-- Вставляем значение в таблицу wal
INSERT INTO wal VALUES (1);

-- Выбираем все записи из таблицы wal для проверки содержимого
SELECT * FROM wal;

-- Получаем текущую позицию в WAL, до которой были вставлены записи
SELECT pg_current_wal_insert_lsn(); -- 0/A4EC6A0

-- Обновляем значение в таблице wal, увеличивая id на 1
UPDATE wal SET id = id + 1;

-- Получаем новую текущую позицию в WAL после обновления записи
SELECT pg_current_wal_insert_lsn(); -- 0/A4EC710

-- Создаем расширение pageinspect для доступа к низкоуровневым функциям инспектирования страниц
CREATE EXTENSION pageinspect;

-- Получаем LSN (Log Sequence Number) для первой страницы таблицы wal
SELECT lsn FROM page_header(get_raw_page('wal', 0));

-- Получаем текущий LSN WAL и текущий LSN вставки WAL
SELECT pg_current_wal_lsn(), pg_current_wal_insert_lsn();

-- Вычисляем разницу между двумя LSN, чтобы понять объем изменений
SELECT '0/A4EC710'::pg_lsn - '0/A4EC6A0'::pg_lsn;

-- Получаем список файлов в директории WAL, показывая первые 10 записей
SELECT * FROM pg_ls_waldir() LIMIT 10;

-- Системные команды для остановки, проверки и запуска кластера PostgreSQL
-- Останавливаем кластер PostgreSQL немедленно, имитируя сбой
-- sudo pg_ctlcluster 16 main stop -m immediate

-- Проверяем контрольные данные кластера PostgreSQL после остановки
-- sudo /usr/lib/postgresql/16/bin/pg_controldata /var/lib/postgresql/16/main/

-- Перезапускаем кластер PostgreSQL
-- sudo pg_ctlcluster 16 main start

```


### Чекпоинты

```
-- Вставка 10,000 записей в таблицу test_pg с использованием функции generate_series для генерации чисел от 1 до 10,000
INSERT INTO test_pg SELECT s.id FROM generate_series(1,10000) AS s(id);

-- Выборка первых 10 записей из таблицы test_pg для проверки содержимого таблицы
SELECT * FROM test_pg LIMIT 10;

-- Подсчет количества грязных (измененных, но не записанных на диск) страниц в буферном кэше PostgreSQL
SELECT count(*) FROM pg_buffercache WHERE isdirty;

-- Получение текущей позиции в WAL (Write-Ahead Log), которая указывает, где последние изменения были зарегистрированы в журнале
SELECT pg_current_wal_insert_lsn(); -- 0/A47F798

-- Выполнение CHECKPOINT для принудительной записи всех грязных страниц и WAL на диск
CHECKPOINT;

-- Подсчет количества грязных страниц после выполнения CHECKPOINT, должно быть 0, если все страницы были успешно записаны
SELECT count(*) FROM pg_buffercache WHERE isdirty;

-- Получение новой текущей позиции в WAL после CHECKPOINT
SELECT pg_current_wal_insert_lsn(); -- 0/A47F880

-- Использование утилиты pg_waldump для анализа содержимого WAL файлов между двумя указанными LSN позициями
sudo /usr/lib/postgresql/16/bin/pg_waldump -p /var/lib/postgresql/16/main/pg_wal -s 0/A47F798 -e 0/A47F880
```


### Настройки

```
-- Проинициализируем тестовый стенд
pgbench -U postgres -h 0.0.0.0 -i test

-- Запустим тест на 30 секунд
pgbench -U postgres -h 0.0.0.0 -T 30 test

-- Включим асинхронный коммит
ALTER SYSTEM SET synchronous_commit = off;
SELECT pg_reload_conf();

-- Запустим тест на 30 секунд
pgbench -U postgres -h 0.0.0.0 -T 30 test

tps = 693.925456
tps = 2448.245475
```