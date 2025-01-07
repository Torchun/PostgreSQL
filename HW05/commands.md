# Пример комманд для анализа настроек производительности

- Посмотрим расположение конфиг файла через psql и idle
```
show config_file;
```

- Так же посмоттреть через функцию:
```
select current_setting('config_file');
```

- Далее смотрим структуру файла postgresql.conf (комменты, единицы измерения и т.д)
```
vi postgresql.conf
```

- Смотрим системное представление 
```
select * from pg_settings;
```

- Далее рассмторим параметры которые требуют рестарт сервера
```commandline
select * from pg_settings where context = 'postmaster';
```

- И изменим параметры `max_connections` через конфиг файл и проверим;
```commandline
select * from pg_settings where name='max_connections';
```

- Смотрим pending_restart
```commandline
select pg_reload_conf();
```

- Смотрим по параметрам вьюху
```commandline
select count(*) from pg_settings;
select unit, count(*) from pg_settings group by unit order by 2 desc;
select category, count(*) from pg_settings group by category order by 2 desc;
select context, count(*) from pg_settings group by context order by 2 desc;
select source, count(*) from pg_settings group by source order by 2 desc;

select * from pg_settings where source = 'override';
```

- Переходим ко вью `pg_file_settings;`
```commandline
select count(*) from pg_file_settings;
select sourcefile, count(*) from pg_file_settings group by sourcefile;

select * from pg_file_settings;
```

- Далее пробуем преминить параметр с ошибкой, смотри что их этого получается
```commandline
select * from pg_file_settings where name='work_mem';
```

- Смотрим проблему с единицами измерения
```commandline
select setting || ' x ' || coalesce(unit, 'units')
from pg_settings
where name = 'work_mem';

select setting || ' x ' || coalesce(unit, 'units')
from pg_settings
where name = 'max_connections';
```

- Далее говорим о том как задать параметр с помощью `alter system`
```commandline
alter system set work_mem = '16 MB';
select * from pg_file_settings where name='work_mem';
```
 
- Сбросить параметр
```
ALTER SYSTEM RESET work_mem;
```

Далее говорим про set config в рамках транзакции

- Установка параметров во время исполнения

Для изменения параметров во время сеанса можно использовать команду SET:
```commandline
=> SET work_mem TO '24MB';
SET
```

Или функцию set_config:
```commandline
=> SELECT set_config('work_mem', '32MB', false);
 set_config 
------------
 32MB
(1 row)
```

Третий параметр функции говорит о том, нужно ли устанавливать значение только для текущей транзакции (true)
или до конца работы сеанса (false). 

Это важно при работе приложения через пул соединений, когда в одном сеансе могут выполняться транзакции разных пользователей.

И для конкретных пользователей и бд
```
create database test;
alter database test set work_mem='8 MB';

create user test with login password 'test';
alter user test set work_mem='16 MB';

SELECT coalesce(role.rolname, 'database wide') as role,
       coalesce(db.datname, 'cluster wide') as database,
       setconfig as what_changed
FROM pg_db_role_setting role_setting
LEFT JOIN pg_roles role ON role.oid = role_setting.setrole
LEFT JOIN pg_database db ON db.oid = role_setting.setdatabase;
```

Далее превреям работу pgbench. Инициализируем необходимые нам таблицы в бд

/usr/pgsql-14/bin/pgbench -i test
/usr/pgsql-14/bin/pgbench -c 50 -j 2 -P 10 -T 60 test

Далее генерируем необходимые параметры в pgtune
И вставляем их в папку conf.d заранее прописав ее в параметры