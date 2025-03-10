
-- #17 EXCEPTIONS
DROP TABLE IF EXISTS t;
CREATE TABLE t(id integer);

DO
$$
DECLARE
    n integer;
BEGIN
    INSERT INTO t(id) VALUES (3);
    SELECT id INTO STRICT n FROM t;
    RAISE NOTICE 'Оператор SELECT INTO выполнился';
EXCEPTION
    WHEN no_data_found THEN
        RAISE NOTICE 'Нет данных';
    WHEN too_many_rows THEN
        RAISE NOTICE 'Слишком много данных';
        RAISE NOTICE 'Строк в таблице: %', (SELECT count(*) FROM t);
END;
$$;

DO $$
DECLARE
    n integer := 1 / 0; -- ошибка в этом месте не перехватывается
BEGIN
    RAISE NOTICE 'OK!';
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'division by zero';
	-- WHEN OTHERS THEN ...
END;
$$;
-- имена и коды ошибок - приложение А

--Ощибки во вложенных блоках
DO $$
BEGIN
    BEGIN
        SELECT 1/0;
        RAISE NOTICE 'Вложенный блок выполнен';
    EXCEPTION
        WHEN division_by_zero THEN
        -- WHEN no_data_found THEN
            RAISE NOTICE 'Ошибка во вложенном блоке';
    END;

    RAISE NOTICE 'Внешний блок выполнен';
EXCEPTION
    WHEN division_by_zero THEN
        RAISE NOTICE 'Ошибка во внешнем блоке';
END;
$$;
-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++



-- #18 SQLSTATE, SQLERRM, GET STACKED DIAGNOSTICS, GET DIAGNOSTICS (и ошибки в процедурах)
DO $$
DECLARE
    n integer;
BEGIN
    RAISE NOTICE 'OK!';
    n = 1/0;
EXCEPTION
    WHEN OTHERS THEN
        RAISE '->  %, ->  %', SQLSTATE, SQLERRM;
END;
$$;

DO
$$
DECLARE
        v_message       text;
        v_detail        text;
        v_hint          text;
        v_ret_sqlstate  text;
		v_context		text;
BEGIN
        RAISE SQLSTATE 'ERR99'
        USING
                message = 'Ошибка!',
                detail  = 'Ощиблись при выполнении функции!',
                hint = 'Обратитесь в службу поддержки';

        RAISE NOTICE 'OK?';
		
        EXCEPTION
                WHEN OTHERS THEN
                        GET STACKED DIAGNOSTICS
                                v_message = message_text,
                                v_detail = pg_exception_detail,
                                v_hint = pg_exception_hint,
                                v_ret_sqlstate = returned_sqlstate,
								v_context = pg_context;
                RAISE NOTICE E'\nmessage = %\ndetail = %\nhint = %\n rsqlstate = %\ncontext = %', v_message, v_detail, v_hint, v_ret_sqlstate, v_context;
END;
$$;
-- см. 42.6.8.1

DROP PROCEDURE IF EXISTS foo();
DROP PROCEDURE IF EXISTS bar();
DROP PROCEDURE IF EXISTS baz();

CREATE PROCEDURE foo()
AS $$
BEGIN
    CALL bar();
END;
$$ LANGUAGE plpgsql;

CREATE PROCEDURE bar()
AS $$
BEGIN
    CALL baz();
END;
$$ LANGUAGE plpgsql;

CREATE PROCEDURE baz()
AS $$
BEGIN
    PERFORM 1 / 0;
END;
$$ LANGUAGE plpgsql;

CALL foo();

-- поличить доступ к сткеку в обработчике исключений
CREATE OR REPLACE PROCEDURE bar()
AS $$
DECLARE
    msg text;
    ctx text;
BEGIN
    CALL baz();
EXCEPTION
    WHEN others THEN
        GET STACKED DIAGNOSTICS
            msg = message_text,
            ctx = pg_exception_context;
        RAISE NOTICE E'\nОшибка: %\nСтек ошибки:\n%\n----', msg, ctx;
END;
$$ LANGUAGE plpgsql;


------------------------------------------------------------------------------------------------------------------------
-- EXCEPTION & save_points
-- На дом...

CREATE OR REPLACE PROCEDURE baz()
AS $$
BEGIN
COMMIT;
END;
$$ LANGUAGE plpgsql;

-- +++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++++




