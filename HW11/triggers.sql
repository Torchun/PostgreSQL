SELECT current_database();

DROP SCHEMA IF EXISTS pract_functions CASCADE;
CREATE SCHEMA pract_functions;
SET search_path = pract_functions, public;

-- #T1  простейший триггер
DROP TABLE IF EXISTS table_for_test;

CREATE TABLE table_for_test
(
	test_id		serial PRIMARY KEY,
	test_param_one	integer NOT NULL,
	test_param_two	integer
    -- ,СONSTRAINT uq_for_test UNIQUE (test_param_one, test_param_two)  -- такой constraint не даст требуемого результата,
	                                                                -- не сработает в случае вставки записей с NULL
	                                                                -- в поле test_param_two
);
-- возможные варианты обеспечения уникальности без триггера:
-- CREATE UNIQUE INDEX ON table_for_test (test_param_one, COALESCE(test_param_two::text, 'NULL'));
INSERT INTO table_for_test (test_param_one, test_param_two) VALUES (76, 76), (76, NULL), (76, NULL);

-- но, тем не менее, реальзуем проверку уникальности триггером,
-- сначала создадим триггерную фунцию:
CREATE OR REPLACE FUNCTION ft_for_test()
RETURNS trigger
AS
$TRIG_FUNC$
BEGIN
	IF EXISTS 	(SELECT 1	FROM table_for_test T
		WHERE T.test_param_one = NEW.test_param_one
		     AND T.test_param_two IS NOT DISTINCT FROM NEW.test_param_two
		     AND T.test_id <> NEW.test_id
		)
	THEN
		RAISE EXCEPTION 'Неуникальный набор параметров!';
	END IF;

	RETURN NEW;
END;
$TRIG_FUNC$
  LANGUAGE plpgsql
  VOLATILE
  SET search_path = pract_functions, public;
  COST 50;

-- Теперь собственно триггер
DROP TRIGGER IF EXISTS tr_for_test ON table_for_test;

CREATE TRIGGER tr_for_test
AFTER INSERT OR UPDATE      -- можно и BEFORE
ON table_for_test
FOR EACH ROW
EXECUTE PROCEDURE ft_for_test();


TRUNCATE TABLE table_for_test;
INSERT INTO table_for_test (test_param_one, test_param_two) VALUES (76, 76), (76, NULL), (76, NULL);

SELECT * FROM table_for_test;

INSERT INTO table_for_test (test_param_one, test_param_two) VALUES (76, 76);
INSERT INTO table_for_test (test_param_one, test_param_two) VALUES (76, NULL);
INSERT INTO table_for_test (test_param_one, test_param_two) VALUES (76, NULL);


-- превратим триггер в CONSTRAINT TRIGGER  и разрешим ему отложенное срабатывание
DROP TRIGGER IF EXISTS tr_for_test ON table_for_test;

CREATE CONSTRAINT TRIGGER tr_for_test
AFTER INSERT OR UPDATE
ON table_for_test
DEFERRABLE
INITIALLY DEFERRED
FOR EACH ROW
EXECUTE PROCEDURE ft_for_test();

ROLLBACK;
START TRANSACTION;

INSERT INTO table_for_test (test_param_one, test_param_two) VALUES (76, 76), (76, NULL), (76, NULL);

UPDATE table_for_test SET test_param_two = test_id;

COMMIT;
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++


-- Еще одна модификация - триггер, не сообщающий об ошибке, а "молча" корректирующий данные:
CREATE OR REPLACE FUNCTION ft_for_test()
RETURNS trigger
AS
$TRIG_FUNC$
BEGIN
	IF EXISTS 	(SELECT 1	FROM table_for_test T
		WHERE T.test_param_one = NEW.test_param_one
		     AND T.test_param_two IS NOT DISTINCT FROM NEW.test_param_two
		     AND T.test_id <> NEW.test_id
		)
	THEN
		NEW.test_param_two = NEW.test_id;
	END IF;

	RETURN NEW;
END;
$TRIG_FUNC$
  LANGUAGE plpgsql
  VOLATILE
  SET search_path = pract_functions, public;
  COST 50;

-- Теперь собственно триггер
DROP TRIGGER IF EXISTS tr_for_test ON table_for_test;

CREATE TRIGGER tr_for_test
BEFORE INSERT OR UPDATE
ON table_for_test
FOR EACH ROW
EXECUTE PROCEDURE ft_for_test();

INSERT INTO table_for_test (test_param_one, test_param_two) VALUES (76, 76), (76, NULL), (76, NULL);

SELECT * FROM table_for_test;
------------------------------------------------------------------------------------------------------------------------

-- более корректный пример CONSTRAINT TRIGGER:
-- https://vladmihalcea.com/postgresql-triggers-isolation-levels/
CREATE TABLE departmens
(
    dep_id      integer PRIMARY KEY,
    dep_name    varchar(31) NOT NULL,
    budget      integer NOT NULL
);

INSERT INTO departmens (dep_id, dep_name, budget) VALUES (1, 'IT', 22000), (2, 'accounting', 11000);

CREATE TABLE employee
(
    emp_id      integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    dep_id      integer REFERENCES departmens(dep_id),
    emp_name    varchar(127) NOT NULL,
    salary      integer NOT NULL CHECK (salary > 0)
);

INSERT INTO employee (dep_id, emp_name, salary)
VALUES  (1, 'Bob', 7000),  (1, 'John', 7000), (1, 'Peter', 7000),
        (2, 'Mary', 5000), (2, 'Alice', 5000);

CREATE OR REPLACE FUNCTION tf_check_budget()
RETURNS trigger
AS
$$
DECLARE
    str text;

BEGIN
    IF  (SELECT sum(salary) FROM employee WHERE dep_id = NEW.dep_id)
        >
        (SELECT budget FROM departmens WHERE dep_id = NEW.dep_id)
    THEN
        /*
        NOTIFY overbudget, 'Overbudget department';
        PERFORM pg_notify('overbudget', format('Overbudget department [id:%s]!', NEW.dep_id));
        RETURN NULL;
        */
        RAISE EXCEPTION 'Overbudget department [id:%]!', NEW.dep_id;
    END IF;
END;
$$  LANGUAGE plpgsql
    SET search_path = pract_functions, public;

CREATE CONSTRAINT TRIGGER trg_check_budget
AFTER INSERT OR UPDATE
ON employee                         -- По хорошему - нужен ещё триггер на табличку departmens!
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE PROCEDURE tf_check_budget();

--LISTEN overbudget;

UPDATE employee SET salary = 17000 WHERE emp_name = 'John';
-- UPDATE pract_functions.employee SET salary = 17000 WHERE emp_name = 'John';
--UNLISTEN *;

SELECT * FROM employee;




-- #T2
DROP TABLE IF EXISTS table_for_test CASCADE;

CREATE TABLE table_for_test
(
	test_id		integer PRIMARY KEY,
	test_str    text
);

-- для иллюстрации порядка срабатывания создадим одну общую триггерную функцию
CREATE OR REPLACE FUNCTION tf_explication()
RETURNS trigger
AS
$$
DECLARE
    data_row record;
    data_str text = '';
BEGIN
    IF TG_LEVEL = 'ROW' THEN
        CASE TG_OP
            WHEN 'DELETE'
                THEN data_row = OLD;
                data_str = OLD::text;
            WHEN 'UPDATE'
                THEN data_row = NEW; data_str = 'UPDATE FROM ' || OLD || ' TO ' || NEW;
            WHEN 'INSERT'
                THEN data_row = NEW; data_str = NEW::text;
        END CASE;
    END IF;

    RAISE NOTICE E'\nG_TABLE_NAME = %\nTG_WHEN = %\nTG_OP = %\nTG_LEVEL = %\ndata_str: %\n -------------', TG_TABLE_NAME, TG_WHEN, TG_OP, TG_LEVEL, data_str;

    RETURN data_row;
END;
$$ LANGUAGE plpgsql;
-- TG_TABLE_NAME, TG_WHEN, TG_OP, TG_LEVEL имеет смысл использовать именно для таких универсальных функций...


-- ...и несколько триггеров

-- "универсальный (на все события, кроме TRUNCATE) триггер BEFORE - FOR EACH STATEMENT
CREATE TRIGGER trg_before_s
BEFORE INSERT OR UPDATE OR DELETE
ON table_for_test
FOR EACH STATEMENT
EXECUTE FUNCTION tf_explication();

-- "универсальный (на все события, кроме TRUNCATE) триггер AFTER - FOR EACH STATEMENT
CREATE TRIGGER trg_after_s
AFTER INSERT OR UPDATE OR DELETE
ON table_for_test
FOR EACH STATEMENT
EXECUTE FUNCTION tf_explication();

-- и два аналогичных триггера FOR EACH ROW
CREATE TRIGGER trg_before_r
BEFORE
INSERT OR UPDATE OR DELETE
ON table_for_test
FOR EACH ROW
EXECUTE FUNCTION tf_explication();

CREATE TRIGGER trg_after_r
AFTER INSERT OR UPDATE OR DELETE
ON table_for_test
FOR EACH ROW
EXECUTE FUNCTION tf_explication();
------------------------------------------------------------------------------------------------------------------------

TRUNCATE TABLE table_for_test;

INSERT INTO table_for_test (test_id, test_str) VALUES (1, 'one'), (2, 'two');

UPDATE table_for_test SET test_str = 'none';

INSERT INTO table_for_test (test_id, test_str) VALUES (11, 'one'), (12, 'two');

DELETE FROM table_for_test WHERE test_str = 'none';

INSERT INTO table_for_test (test_id, test_str) VALUES (1, 'for conflict'), (900, 'NO conflict')
ON CONFLICT (test_id) DO UPDATE SET test_str = EXCLUDED.test_str;
-- INSERT с ON CONFLICT приводит к тому, что срабатывают триггеры и на вставку, и на обновление
------------------------------------------------------------------------------------------------------------------------


-- Использование transition tables
DROP TABLE IF EXISTS table_for_test CASCADE;

CREATE TABLE table_for_test
(
	test_id		integer PRIMARY KEY,
	test_str    text
);

CREATE OR REPLACE FUNCTION tf_use_tables_updt()
RETURNS trigger
AS
$$
DECLARE
    data_row record;
BEGIN

    FOR data_row
    IN
    SELECT * FROM tbl_old
    LOOP
        RAISE NOTICE 'old_data: %', data_row;
    END LOOP;

    FOR data_row
    IN SELECT * FROM tbl_new
    LOOP
        RAISE NOTICE 'new_data - %', data_row;
    END LOOP;

    RETURN NULL;
END;
$$ LANGUAGE plpgsql;



CREATE TRIGGER trg_after_updt
AFTER UPDATE    -- transitions доступны только в триггерах для одного события!
ON table_for_test
REFERENCING
    OLD TABLE AS tbl_old
    NEW TABLE AS tbl_new
FOR EACH STATEMENT
EXECUTE FUNCTION tf_use_tables_updt();

TRUNCATE TABLE table_for_test;

INSERT INTO table_for_test (test_id, test_str) VALUES (1, 'one'), (2, 'two');

UPDATE table_for_test SET test_str = 'none';
------------------------------------------------------------------------------------------------------------------------

-- Поскольку триггеры AFTER ROW срабатывают после выполнения всей операции, переходные таблицы можно использовать и в них
-- Но зачем, если есть возможность обратиться к записям OLD & NEW?
------------------------------------------------------------------------------------------------------------------------


DROP TABLE IF EXISTS grades CASCADE;
DROP TABLE IF EXISTS subjects CASCADE;
DROP TABLE IF EXISTS students CASCADE;

-- Триггеры INSTEAD OF:
CREATE TABLE IF NOT EXISTS students
(
    student_id   integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    student_name varchar(63) NOT NULL UNIQUE
);


CREATE TABLE IF NOT EXISTS subjects
(
    subject_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    subject_name varchar(63) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS grades
(
    student_id  integer REFERENCES students (student_id) ON UPDATE CASCADE ON DELETE CASCADE,
    subject_id  integer REFERENCES subjects (subject_id) ON UPDATE CASCADE ON DELETE CASCADE,
    grade       smallint CHECK (grade > 1 AND grade <=5),

    CONSTRAINT pk_grades PRIMARY KEY (student_id, subject_id)
);

CREATE VIEW students_grades
AS
SELECT ST.student_name, SB.subject_name, G.grade
FROM students ST
INNER JOIN grades G ON G.student_id = ST.student_id
INNER JOIN subjects SB ON SB.subject_id = G.subject_id;

CREATE OR REPLACE FUNCTION tf_edit_grades()
RETURNS trigger
AS
$$
DECLARE
    row_dbg record;
BEGIN
    CASE TG_OP
        WHEN 'INSERT' THEN
            WITH ins_st
            AS  (
                INSERT INTO students (student_name) VALUES (NEW.student_name)
                ON CONFLICT (student_name)
                DO UPDATE SET student_name = EXCLUDED.student_name -- чтобы иметь возможность вернуть student_id
                RETURNING student_id
                ),
            ins_sb
            AS  (
                INSERT INTO subjects (subject_name) VALUES (NEW.subject_name)
                ON CONFLICT (subject_name)
                DO UPDATE SET subject_name = EXCLUDED.subject_name -- чтобы иметь возможность вернуть student_id
                RETURNING subject_id
                )
            INSERT INTO grades (student_id, subject_id, grade)
            SELECT ST.student_id, SB.subject_id, NEW.grade
            FROM ins_st ST, ins_sb SB
            ON CONFLICT (student_id, subject_id)
            DO UPDATE SET grade = EXCLUDED.grade;

            RETURN NEW;

        WHEN 'DELETE' THEN
            DELETE FROM grades G
            USING students, subjects
            WHERE G.student_id = students.student_id
              AND G.subject_id = subjects.subject_id
              AND students.student_name =  OLD.student_name
              AND subjects.subject_name = OLD.subject_name;

            RETURN OLD;

        WHEN 'UPDATE' THEN
            UPDATE grades
            SET grade = NEW.grade
            WHERE student_id = (SELECT student_id FROM students WHERE student_name = NEW.student_name)
              AND subject_id = (SELECT subject_id FROM subjects WHERE subject_name = NEW.subject_name);

            RETURN NEW;
    END CASE;
END
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_edit_grades
INSTEAD OF INSERT OR UPDATE OR DELETE
ON students_grades
FOR EACH ROW
EXECUTE FUNCTION tf_edit_grades();

INSERT INTO students_grades (student_name, subject_name, grade) VALUES ('John', 'Philosophy', 3);
INSERT INTO students_grades (student_name, subject_name, grade) VALUES ('Peter', 'Algebra', 2);

SELECT * FROM students;
SELECT * FROM subjects;
SELECT * FROM grades;
SELECT * FROM students_grades;

DELETE FROM students_grades WHERE student_name = 'John';
DELETE FROM students_grades WHERE student_name = 'Peter';

UPDATE students_grades
SET grade = 5
WHERE student_name = 'Peter'
  AND subject_name = 'Algebra';
--==========================================================================================================


-- #T3  событийные триггеры
/*
DROP EVENT TRIGGER IF EXISTS etrg_log_actions;
DROP EVENT TRIGGER IF EXISTS etf_log_actions;
DROP TRIGGER IF EXISTS etf_log_actions;
*/

SELECT current_database();
DROP SCHEMA IF EXISTS pract_functions CASCADE;
CREATE SCHEMA pract_functions;
SET search_path = pract_functions, public;

-- рабочие смены администраторов
CREATE TABLE workshifts
(
    admin_name  name PRIMARY KEY,
    shift_beg   time without time zone,
    shift_end   time without time zone
);

INSERT INTO workshifts (admin_name, shift_beg, shift_end)
VALUES  ('mary', '00:00:00', '12:00:00'),
        ('john', '12:00:00', '23:59:59');


-- журнал
CREATE TABLE actions_log
(
    log_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    admin_name  name,
    action_name text,
    action_obj  text,
    action_time timestamp with time zone DEFAULT now()      -- ???
);

--REVOKE USAGE ON SCHEMA pract_functions FROM mary;
--REVOKE USAGE ON SCHEMA pract_functions FROM john;
DROP USER IF EXISTS mary;
DROP USER IF EXISTS john;
CREATE USER mary LOGIN SUPERUSER PASSWORD '12345678';
CREATE USER john LOGIN SUPERUSER PASSWORD '12345678';
GRANT USAGE ON SCHEMA pract_functions TO mary;
GRANT USAGE ON SCHEMA pract_functions TO john;

DROP EVENT TRIGGER IF EXISTS etrg_log_actions;
DROP FUNCTION IF EXISTS etf_event_process();

DROP EVENT TRIGGER IF EXISTS etrg_log_actions_del;
DROP FUNCTION IF EXISTS etf_event_process_del();

CREATE OR REPLACE FUNCTION etf_event_process()
RETURNS event_trigger
AS
$$
BEGIN
    IF session_user IN ('mary', 'john')   -- "предохранитель"
    THEN
        IF NOT EXISTS   (
                        SELECT 1 FROM workshifts
                        WHERE admin_name = session_user AND now()::time BETWEEN shift_beg AND shift_end
                        )
        THEN	-- не разрешаем работать не в свою смену
            RAISE EXCEPTION 'Создание и изменение объектов БД не разрешено!';
        END IF;
    END IF;

    INSERT INTO actions_log (admin_name, action_name, action_obj)
    SELECT session_user, tg_tag, object_identity FROM pg_event_trigger_ddl_commands();
END;
$$  LANGUAGE plpgsql
    SET search_path = pract_functions, public;  -- !!!


CREATE OR REPLACE FUNCTION etf_event_process_del()
RETURNS event_trigger
AS
$$
BEGIN
    IF session_user IN ('mary', 'john')   -- "предохранитель"
    THEN
        IF NOT EXISTS   (
                        SELECT 1 FROM workshifts
                        WHERE admin_name = session_user AND now()::time BETWEEN shift_beg AND shift_end
                        )
        THEN	-- не разрешаем работать не в свою смену
            RAISE EXCEPTION 'Удаление объектов БД не разрешено!';
        END IF;
    END IF;

    INSERT INTO actions_log (admin_name, action_name, action_obj)
    SELECT session_user, 'DROP ' || object_type, object_identity FROM pg_event_trigger_dropped_objects();
END;
$$  LANGUAGE plpgsql
    SET search_path = pract_functions, public;  -- !!!


CREATE EVENT TRIGGER etrg_log_actions
ON ddl_command_end
EXECUTE FUNCTION pract_functions.etf_event_process();

CREATE EVENT TRIGGER etrg_log_actions_del
ON sql_drop
EXECUTE FUNCTION pract_functions.etf_event_process_del();

DROP TABLE pract_functions.t_tmp;
DROP TABLE IF EXISTS pract_functions.t_tmp;

CREATE TABLE t_tmp (i integer);
ALTER TABLE t_tmp ADD COLUMN n integer;

SELECT * FROM actions_log ORDER BY action_time;

-- Обратите внимание, что при удалении таблицы удаляются типы (2 шт!)
---------------------------------------------------------------------------------------------------------



