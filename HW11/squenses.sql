SELECT current_database();
DROP SCHEMA IF EXISTS pract_functions CASCADE;
CREATE SCHEMA pract_functions;
SET search_path = pract_functions, public;

CREATE TABLE the_table
(
    the_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    the_str text
);


DROP TABLE the_table;
CREATE TABLE the_table
(
    the_id  integer GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
    parent  integer DEFAULT currval('the_table_the_id_seq'::regclass) REFERENCES the_table (the_id),
    the_str text
);

INSERT INTO the_table (the_str) VALUES ('раз'),  ('два'),  ('три');
INSERT INTO the_table (parent, the_str) VALUES (2, 'два-два');
SELECT * FROM the_table;

CREATE SEQUENCE IF NOT EXISTS custom_sq START 800 MINVALUE 35;
SELECT nextval('custom_sq'::regclass), currval('custom_sq'::regclass);
SELECT setval ('custom_sq'::regclass, 33, true);    -- err!
SELECT setval ('custom_sq'::regclass, 35, true);
SELECT nextval('custom_sq'::regclass), currval('custom_sq'::regclass);
SELECT setval ('custom_sq'::regclass, 35, false);
SELECT nextval('custom_sq'::regclass), currval('custom_sq'::regclass);

SELECT lastval();

-- SEQUENCE - "нетранзакционный" объект!
SELECT * FROM the_table;

START TRANSACTION;
INSERT INTO the_table (the_str) VALUES ('раз!!!'),  ('два!!!'),  ('три!!!');
ROLLBACK;

INSERT INTO the_table (the_str) VALUES ('...');

SELECT * FROM the_table;

DROP SEQUENCE custom_sq;


