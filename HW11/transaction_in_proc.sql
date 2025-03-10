SELECT current_database();

DROP SCHEMA IF EXISTS pract_functions CASCADE;
CREATE SCHEMA IF NOT EXISTS pract_functions;
SET search_path = pract_functions, public;

CREATE TABLE tx (str text);

CREATE PROCEDURE try_trans()
AS
$$
BEGIN
    INSERT INTO tx (str) VALUES ('dddddd');
    RAISE NOTICE 'asd';
    ROLLBACK;
END;
$$ LANGUAGE plpgsql;

-- процедура должна начинать новую транзакцию, то есть не должна выполняться в контексте уже начатой ранее
CALL try_trans();
INSERT INTO tx (str) VALUES ('------');
-----------------------------------------------------------------------------------------------------------------------

CREATE PROCEDURE try_trans2()
AS
$$
BEGIN
    INSERT INTO tx (str) VALUES ('dddddd');
    COMMIT;
END;
$$ LANGUAGE plpgsql;

CREATE PROCEDURE try_trans1()
AS
$$
BEGIN
    CALL try_trans2();
END;
$$ LANGUAGE plpgsql;

CREATE PROCEDURE try_trans0()
AS
$$
BEGIN
    CALL try_trans1();
END;
$$ LANGUAGE plpgsql;

CALL  try_trans2();

SELECT * FROM tx;

--НО!
CREATE OR REPLACE FUNCTION try_trans_func()
RETURNS void
AS
$$
BEGIN
    CALL try_trans2();
END;
$$ LANGUAGE plpgsql;

SELECT * FROM try_trans_func();     --не работает по понятным причинам (как закомитить транзакцию посреди селекта?)