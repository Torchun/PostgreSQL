/* trigger on F-TABLE	*/
--------------------------------------------------------------

/* таблица на удаленном сервере:
-- DROP TABLE book_store.book;

CREATE TABLE book_store.book (
	book_id		serial NOT NULL,
	book_name	varchar(255) NOT NULL,
	isbn		varchar(18) NULL,
	published	smallint NULL,
	genre_id 	integer NOT NULL,
	
	CONSTRAINT book_isbn_key UNIQUE (isbn),
	CONSTRAINT book_pkey PRIMARY KEY (book_id)
);
CREATE INDEX i1_book ON book_store.book USING btree (genre_id);
CREATE INDEX ix_genre_id ON book_store.book USING btree (genre_id);


-- book_store.book foreign keys

-- ALTER TABLE book_store.book ADD CONSTRAINT book_genre_id_fkey FOREIGN KEY (genre_id) REFERENCES book_store.genre(genre_id) ON DELETE RESTRICT ON UPDATE CASCADE;
*/

DROP FOREIGN TABLE IF EXISTS books.book;
CREATE FOREIGN TABLE IF NOT EXISTS books.book
(
	-- book_id		serial,
	book_name	varchar(255),
	isbn		varchar(18),
	published	smallint,
	genre_id	integer
)
SERVER vmserver
OPTIONS (schema_name 'book_store');
--------------------------------------------------------------
SELECT * FROM books.book;


CREATE OR REPLACE FUNCTION books.ft_ins_book ()
RETURNS trigger
AS
$ft$
BEGIN
	IF NEW.book_name = 'Просто книга'
	THEN
		NEW.book_name = 'Нет, это не просто книга!';
	END IF;

	RETURN NEW;
END;
$ft$
	LANGUAGE plpgsql
	SECURITY DEFINER;

CREATE TRIGGER tr_ins_book
BEFORE INSERT
ON books.book
FOR EACH ROW
EXECUTE PROCEDURE books.ft_ins_book ();

INSERT INTO books.book (book_name, genre_id) VALUES ('Просто книга', 1);
------------------------------------------------------------------------
-- =====================================================================