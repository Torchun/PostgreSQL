-- посмотрим виртуальный id транзакции
begin transaction

SELECT txid_current(); -- 737

CREATE TABLE test(i int);
INSERT INTO test VALUES (10),(20),(30);

select * from test;

SELECT i, xmin, xmax, cmin, cmax, ctid FROM test;

commit transaction

-- посмотрим мертвые туплы
SELECT relname, n_live_tup, n_dead_tup, trunc(100*n_dead_tup/(n_live_tup+1))::float "ratio%", last_autovacuum FROM pg_stat_user_tables WHERE relname = 'test';

update test set i = 100 where i = 10;

CREATE EXTENSION pageinspect;

SELECT lp as tuple, t_xmin, t_xmax, t_field3 as t_cid, t_ctid FROM heap_page_items(get_raw_page('test',0));
SELECT * FROM heap_page_items(get_raw_page('test',0));

-- попробуем изменить данные и откатить транзакцию и посмотреть
begin

SELECT txid_current(); -- 740

insert into test values(50),(60),(70);

select * from test;

rollback;

-- объяснения про побитовую маску
-- https://habr.com/ru/company/postgrespro/blog/445820/

-----vacuum
drop table test;
CREATE TABLE test(i int);

insert into test(i) select g.x from generate_series(1, 10000) as g(x);
select count(*) from test;
select *, xmax, xmin from test limit 10;

delete from test where i > 5000;

vacuum verbose test;
SELECT lp as tuple, t_xmin, t_xmax, t_field3 as t_cid, t_ctid FROM heap_page_items(get_raw_page('test',0));
SELECT pg_size_pretty(pg_total_relation_size('test')); -- 216 kB

vacuum full test;
SELECT pg_size_pretty(pg_total_relation_size('test')); -- 184 kB

SELECT name, setting, context, short_desc FROM pg_settings WHERE name like 'vacuum%';

------Autovacuum
SELECT name, setting, context, short_desc FROM pg_settings WHERE name like 'autovacuum%';

SELECT * FROM pg_stat_activity WHERE query ~ 'autovacuum'

select c.relname,
current_setting('autovacuum_vacuum_threshold') as av_base_thresh,
current_setting('autovacuum_vacuum_scale_factor') as av_scale_factor,
(current_setting('autovacuum_vacuum_threshold')::int +
(current_setting('autovacuum_vacuum_scale_factor')::float * c.reltuples)) as av_thresh,
s.n_dead_tup
from pg_stat_user_tables s join pg_class c ON s.relname = c.relname
where s.n_dead_tup > (current_setting('autovacuum_vacuum_threshold')::int
+ (current_setting('autovacuum_vacuum_scale_factor')::float * c.reltuples));


CREATE TABLE student(
  id serial,
  fio char(100)
) WITH (autovacuum_enabled = off);


INSERT INTO student(fio) SELECT 'noname' FROM generate_series(1, 500000);

SELECT pg_size_pretty(pg_total_relation_size('student')); -- 67 MB

update student set fio = 'name';

SELECT relname, n_live_tup, n_dead_tup, trunc(100*n_dead_tup/(n_live_tup+1))::float "ratio%", last_autovacuum FROM pg_stat_user_tables WHERE relname = 'student';

ALTER TABLE student SET (autovacuum_enabled = on);

vacuum full student;

----
SHOW vacuum_freeze_min_age;
SHOW vacuum_freeze_table_age;
SHOW autovacuum_freeze_max_age;

