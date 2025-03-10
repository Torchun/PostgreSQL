SELECT current_database();

DROP SCHEMA IF EXISTS pract_functions CASCADE;
CREATE SCHEMA IF NOT EXISTS pract_functions;
SET search_path = pract_functions, public;


-- #5 КУРСОРЫ
CREATE TABLE IF NOT EXISTS tab4curs
(
    the_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    the_str text
);

INSERT INTO tab4curs (the_str) VALUES ('раз'), ('два'), ('три');

-- несвязанные
DO
$$
DECLARE
	the_record	tab4curs;
	the_cursor	refcursor;	-- несвязанная переменная, может быть использована с любым запросом
BEGIN

	OPEN the_cursor FOR SELECT * FROM tab4curs;	-- "OPEN" - эквивалент "DECLARE CURSOR"

	FETCH the_cursor INTO the_record;
	RAISE NOTICE '--->%', the_record;

	FETCH the_cursor INTO the_record;
	RAISE NOTICE '--->%', the_record;

	FETCH the_cursor INTO the_record;
	RAISE NOTICE '--->%', the_record;

	MOVE RELATIVE -2 FROM the_cursor;
	FETCH the_cursor INTO the_record;
	RAISE NOTICE '--->%', the_record;

	MOVE PRIOR FROM the_cursor;
	FETCH the_cursor INTO the_record;
	RAISE NOTICE '--->%', the_record;

	CLOSE the_cursor;
END;
$$;


-- несвязанные
DO
$$
DECLARE
	the_record	tab4curs;
	the_cursor	refcursor;	-- несвязанная переменная, может быть использована с любым запросом
BEGIN

	OPEN the_cursor FOR SELECT * FROM tab4curs FOR UPDATE;	-- "OPEN" - эквивалент "DECLARE CURSOR"
	                                                        -- "FOR UPDATE" обязателен, если будет "UPDATE"

	FETCH the_cursor INTO the_record;
	RAISE NOTICE '--->%', the_record;

	FETCH the_cursor INTO the_record;
	RAISE NOTICE '--->%', the_record;

	UPDATE tab4curs     -- необходим "FOR UPDATE"
	SET the_str = 'две тысячи сто сорок семь'

	WHERE CURRENT OF the_cursor;
	FETCH the_cursor INTO the_record;
	RAISE NOTICE '--->%', the_record;

	CLOSE the_cursor;
END;
$$; -- но с "FOR UPDATE" курсор может быть только NO SCROLL

SELECT * FROM tab4curs ORDER BY the_id;

-- связанные
DO
$$
DECLARE
	the_record	tab4curs;
	the_cursor	cursor FOR SELECT * FROM tab4curs;		-- в цикле FOR (см.ниже) можно использовать только
														-- "связанную" переменную
BEGIN
	FOR the_record IN the_cursor
	LOOP
		RAISE NOTICE '--->%', the_record;
	END LOOP;

	--CLOSE the_cursor;	-- при использовании "связанной" переменной курсор закрывать не надо
END;
$$;

DO
$$
DECLARE
	the_record	tab4curs;
	the_cursor	NO SCROLL cursor FOR SELECT * FROM tab4curs;

BEGIN
	OPEN the_cursor;

	FOR i IN 1..10
	LOOP
		FETCH the_cursor INTO the_record;

		RAISE NOTICE '--->%', the_record;
	END LOOP;

    CLOSE the_cursor;
END;
$$;


DO
$$
DECLARE
    id2select   integer;
	the_record	tab4curs;
	the_cursor	NO SCROLL cursor FOR SELECT * FROM tab4curs WHERE the_id > id2select;

BEGIN
    id2select = 2;

	FOR the_record IN the_cursor
	LOOP
		RAISE NOTICE '--->%', the_record;
	END LOOP;

	RAISE NOTICE 'а были ли данные? - %', FOUND;
END;
$$;

-- функция, возвращающая курсор
CREATE OR REPLACE FUNCTION get_cur()
RETURNS refcursor
AS
$$
DECLARE
    cur refcursor;
BEGIN
    OPEN cur FOR SELECT the_str FROM tab4curs;
    RETURN cur;
END;
$$ VOLATILE
        LANGUAGE plpgsql
        -- SET search_path = pract_functions, public
        ;

-- использование
DO
$$
DECLARE
        crs         refcursor;
        v_the_str   text;
BEGIN
        crs = get_cur();    -- ! понятно ли, что без SELECT'а?

        FETCH NEXT FROM crs INTO v_the_str;
        RAISE NOTICE '-->>> %', v_the_str;
END;
$$;

-- или так:
CREATE OR REPLACE FUNCTION get_cur_by_name(p_cur refcursor )
RETURNS refcursor
AS
$$

BEGIN
    OPEN p_cur FOR SELECT the_str FROM tab4curs;
    RETURN p_cur;
END;
$$ VOLATILE
        LANGUAGE plpgsql
        -- SET search_path = pract_functions, public
        ;


START TRANSACTION;  -- Обязательно!
SELECT * FROM get_cur_by_name('my_local_cursor');
FETCH ALL FROM my_local_cursor;
COMMIT;
-- аналогично можно вернуть несклолько курсоров
------------------------------------------------------------------------------------------------------------------------