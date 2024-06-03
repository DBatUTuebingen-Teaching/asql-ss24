-- Query the DuckDB system catalog for the supported data types:

SELECT t.type_name AS "𝖽ata types"
FROM   duckdb_types AS t
WHERE  t.database_name = 'memory';

-----------------------------------------------------------------------

DROP TABLE IF EXISTS T;

CREATE TABLE T (a int PRIMARY KEY,
                b text,
                c boolean,
                d int);

INSERT INTO T VALUES
  (1, 'x',  true, 10),
  (2, 'y',  true, 40),
  (3, 'x', false, 30),
  (4, 'y', false, 20),
  (5, 'x',  true, NULL);

-----------------------------------------------------------------------
-- (Implicit) Type casts

-- Runtime type conversion
SELECT 6.2 :: int;                  -- ➝ 6
SELECT 6.6 :: int;                  -- ➝ 7
SELECT CAST('2024-05-04' AS date);  -- ➝ 2024-05-04 (May the Force ...)


-- Implicit conversion if target type is known (here: schema of T)
INSERT INTO T(a,b,c,d) VALUES (6.2, NULL, 'true', '0');
--                              ↑     ↑      ↑     ↑
--                             int  text  boolean int


-- Literal input syntax using '...' (cast from text to any other type):
SELECT booleans.yup :: boolean, booleans.nope :: boolean
FROM   (VALUES ('true', 'false'),
               ('True', 'False'),  -- case does not matter
               ('t',    'f'),
               ('1',    '0')) AS booleans(yup, nope);

SELECT '{"x":42, "ys":[4,2], "z":"fortytwo"}' :: json;

-- May use $‹id›$...$‹id›$ instead of '...'
SELECT $${"x":42, "ys":[4,2], "x'":"fortytwo"}$$ :: json;

-- Type casts perform computation, validity checks, and thus are *not* for free:
SELECT '{"x":42, "ys":[4;2], "z":"fortytwo"}' :: json;
--                      ↑
--              ⚠️ comma expected

-- Implicit cast from text to target during *input conversion*:
DELETE FROM T;

INSERT INTO T(a,b,c,d)
  SELECT t.*
  FROM   read_csv('~/AdvancedSQL/slides/Week03/live/text-input.csv', nullstr = '▢') AS t;

TABLE T;

-----------------------------------------------------------------------
-- Text data types

SELECT '01234' :: char(3);   -- specifying a "maximum length" has no effect


-- Character length vs. storage size in bytes
-- (DuckDB built-in functions length() vs strlen())
SELECT t.c,
       length(t.c)          AS "# chars",
       strlen(t.c)          AS "# bytes",
       length_grapheme(t.c) AS "# graphemes",
       encode(t.c)          AS bytes
FROM   (VALUES ('x'),
               ('⚠'), -- ⚠ = U+26A0, in UTF8: 0xE2 0x9A 0xA0
               ('👩🏾')
       ) AS t(c);

-- Grapheme: sequence of one or more code points that are displayed
--           as a single, graphical unit that a reader recognizes
--           as a single element of the writing system.

-----------------------------------------------------------------------
-- Exact arithmetics with NUMERIC(w,s)

-- Arithmetics over type double suffers from the usual binary
-- number representation problem (see https://0.30000000000000004.com)
--
SELECT 0.1 :: double + 0.2 :: double AS oops;

-- ┌─────────────────────┐
-- │        oops         │
-- │       double        │
-- ├─────────────────────┤
-- │ 0.30000000000000004 │
-- └─────────────────────┘

SELECT 0.1 + 0.2 AS "ok!";

-- ┌──────────────┐
-- │     ok!      │
-- │ decimal(3,1) │ ← DuckDB defaults to type decimal(2,1) for 0.1
-- ├──────────────┤   (infers wider decimal(3,1) for result)
-- │          0.3 │
-- └──────────────┘

-----------------------------------------------------------------------
-- Overhead of NUMERIC(w,0) ≡ NUMERIC(w) arithmetics

-- numeric(19,0) or wider is represented by int128:
--
--          ┌────19 digits────┐
SELECT log2(9999999999999999999);  -- 63.1166 ...: need 64 bits + sign ⇒ use int128


-- The following two queries to "benchmark" the
-- performance of numeric(.,.) vs. int arithmetics
-- (MAX aggregation to avoid generation of sizeable result)

.timer on

-- 1B rows of 16-byte numerics
WITH one_billion_rows(x) AS (
  SELECT t.x :: numeric(19,0)  -- numeric(w,0) with w ⩾ 19 yields identical timings
  FROM   generate_series(1, 1000000000) AS t(x)
)
SELECT MAX(t.x + t.x) AS add
FROM   one_billion_rows AS t;

-- 1B rows of width 8-byte integers
WITH one_billion_rows(x) AS (
  SELECT t.x
  FROM   generate_series(1, 1000000000) AS t(x)
)
SELECT MAX(t.x + t.x) AS add
FROM   one_billion_rows AS t;

-----------------------------------------------------------------------
-- Date/Time/Timestamps/Intervals

-- Support for symbolic time zone names
INSTALL icu;
LOAD icu;


SELECT '1986-04-06' :: date;

SELECT '1969-07-20 20:17:00+00' :: timestamp AS "moon landing";
--      └───┬────┘↑└────┬────┘
--      date part ⎵  time part

SELECT today()               AS "today (date)",
       today() :: timestamp  AS "today (timestamp)",
       now()                 AS "now (timestamptz)";

SELECT '1 year 2 months 3 days 4 hours 5 minutes 6 seconds' :: interval;

SELECT interval(60 * 60) seconds AS "seconds in an hour";


-- Date/time arithmetics with intervals
.columns

SELECT '2035-08-31' :: date - today()                              AS retirement,
       today() + '30 days' :: interval                             AS in_one_month,
       today() + 2 * interval(1) month                             AS in_two_months,
       now() - today() :: timestamp                                AS since_midnight,
       extract(hours from now() - today() :: timestamp)            AS hours_since_midnight,
       age('1968-08-26' :: date)                                   AS age;

.rows


--                year    month  day               ignore time 00:00:00, keep date only
--                 ↓        ↓     ↓                         ↓
SELECT (make_date(2024, months.m, 1) - '1 day'::interval)::date AS last_day_of_month
FROM   generate_series(1,12) AS months(m);


-- DuckDB's date/time library is extensive...
--
SELECT last_day(make_date(2024, months.m, 1)) AS last_day_of_month
FROM   generate_series(1,12) AS months(m);



SELECT timezones.tz AS timezone,
       now() -- uses default local time zone
         -
       (now()::timestamp::text || ' ' || timezones.tz)::timestamptz AS difference
FROM   (VALUES ('America/New_York'),
               ('Europe/Berlin'),
               ('Asia/Tokyo'),
               ('PST'),
               ('UTC'),
               ('US/Mountain'),
               ('Etc/GMT+5')
       ) AS timezones(tz)
ORDER BY difference;

-----------------------------------------------------------------------
-- Enumerations

DROP TYPE IF EXISTS episode;
CREATE TYPE episode AS ENUM
  ('ANH', 'ESB', 'TPM', 'AOTC', 'ROTS', 'ROTJ', 'TFA', 'TLJ', 'TROS');

DROP TABLE IF EXISTS starwars;
CREATE TABLE starwars(film    episode PRIMARY KEY,
                      title   text,
                      release date);

INSERT INTO starwars(film,title,release) VALUES
    ('TPM',  'The Phantom Menace',      '1999-05-19'),
    ('AOTC', 'Attack of the Clones',    '2002-05-16'),
    ('ROTS', 'Revenge of the Sith',     '2005-05-19'),
    ('ANH',  'A New Hope',              '1977-05-25'),
    ('ESB',  'The Empire Strikes Back', '1980-05-21'),
    ('ROTJ', 'Return of the Jedi',      '1983-05-25'),
    ('TFA',  'The Force Awakens',       '2015-12-18'),
    ('TLJ',  'The Last Jedi',           '2017-12-15'),
    ('TROS', 'The Rise of Skywalker',   '2019-12-19');
--     ↑              ↑                        ↑
-- ::episode       ::text                    ::date

TABLE starwars;

INSERT INTO starwars(film,title,release) VALUES
  ('R1', 'Rogue One', '2016-12-15');
--   ↑
-- ⚠️ not an episode value
-- Conversion Error: Could not convert string 'R1' to UINT8


-- Order of enumerated type (almost) yields the Star Wars Machete order
SELECT s.*
FROM   starwars AS s
ORDER BY s.film; -- s.release; -- yields chronological order


-----------------------------------------------------------------------
-- Bit strings

-- Sets every third bit
SELECT bitstring_agg(bit.pos, 0, 10) AS bits  -- ⚠️ bit at pos 0 is leftmost
FROM   generate_series(0,10,3) AS bit(pos);


-- Queries Q1 and Q2 perform the same computation:
--
-- Q1
SELECT setseed(0.42);

SELECT COUNT(DISTINCT (random()*100)::int)
FROM   generate_series(1,100);

-- Q2
SELECT setseed(0.42);

SELECT bit_count(bitstring_agg((random()*100)::int, 0, 100))
FROM   generate_series(1,100);


-----------------------------------------------------------------------
-- Binary byte sequences

-- See extra file glados.sql (requires *.wav files).


-----------------------------------------------------------------------
-- JSON

INSTALL json;
LOAD json;

-- json
VALUES (1, json('{ "b":1, "a":2 }')),         -- ← pair order and ...
       (2, json('{ "a":1, "b":2, "a":3 }')),  -- ← ... duplicates preserved
       (3, json('[ 0,   false,null ]'));      -- ← whitespace minified


--  Navigating a JSON value using binary operator ->
SELECT (json('{ "a":0, "b": { "b₁":[1,2], "b₂":3 } }')->'b'->'b₁'->'1') :: int + 40;
--                                                                      ↑
--                                     extracts a json value, cast for computation

SELECT json('{ "a":0, "b": { "b₁":[1,2], "b₂":3 } }')->'b'->'b₁'->>'1';
--                                                               ↑
--                                      variant operator ->> extracts a text value


--  Navigating a JSON value using JSONPath syntax
--    (JSONPath paths represented as quoted literals of type text)
--
--    JSON describes tree-shaped data:
--
--                   root $       {}               level 0
--                              ᵃ╱  ╲ᵇ
--                              𝟬    {}            level 1
--                                 ᶜ╱  ╲ᵈ
--                                 []   𝟯          level 2
--                               ⁰╱  ╲¹
--                               𝟭    𝟮            level 3

SELECT json_extract(json('{ "a":0, "b": { "c":[1,2], "d":3 } }'),
                    -- '$'                        -- root value
                    -- '$.*'                   -- all child values of the root
                    -- '$.a'                   -- child a of the root
                    -- '$.b.d'                 -- grandchild d below child b
                    '$.b.c[1]'              -- 2nd array element of array c
                    -- '$.b.c[*]'              -- all array elements in array c
                    -- '$.b.c[#-2]'            -- second to last element in array c
                    ) AS j;


-- Equivalent (uses binary operator ->:
SELECT json('{ "a":0, "b": { "c":[1,2], "d":3 } }')->'$.b.c[1]';


-------------------------------
-- Bridging between JSON Objects and SQL Rows

--  Cast JSON object o into row value t
SELECT json('{"a":1,"b":true}') :: row(a int, b boolean) AS t;

-- Once we have turned JSON object o into a SQL row value t,
-- we can simply navigate its structure using SQL's dot notation:
--
SELECT obj.j,
       obj.j->'b'->'d'                                     AS d1,
       (obj.j :: row(a int, b row(c boolean, d text))).b.d AS d2  -- .b.d: SQL field access
FROM   (VALUES (json('{"a":1, "b":{"c":true,  "d":"one"}}')),
               (json('{"a":2, "b":{"c":false, "d":"two"}}'))) AS obj(j);


--  Turn row values t into JSON objects o
SELECT json(t) AS o
FROM   T AS t;


-------------------------------
-- Constructing JSON values From a Table of Inputs
--

-- ⚠️ json_group_array(･) and json_group_object(･,･)
--    are aggegrate functions

SELECT json_group_array(t.b) AS bs,
       json_group_array(t.d) AS ds
FROM   T AS t;


-- Invalid Input Error: Map keys must be unique.
SELECT json_group_object(t.b, t.c) AS o
FROM   T AS t;

-- OK (text || int casts rhs to text)
SELECT json_group_object(t.b || t.a, t.c) AS o
FROM   T AS t;


-----------------------------------------------------------------------
-- Sequences

DROP SEQUENCE IF EXISTS seq;
CREATE SEQUENCE seq START 41 MAXVALUE 42 CYCLE;

SELECT nextval('seq');      -- ⇒ 41
SELECT nextval('seq');      -- ⇒ 42
SELECT currval('seq');      -- ⇒ 42
SELECT nextval('seq');      -- ⇒ 1   (wrap-around)

-----------------------------------

DROP SEQUENCE IF EXISTS T_keys CASCADE;
CREATE SEQUENCE T_keys START 100 INCREMENT 10;
DROP TABLE IF EXISTS auto_T;
CREATE TABLE auto_T (k int DEFAULT nextval('T_keys'),
                     a int ,
                     b text,
                     c boolean,
                     d int);


--                    column k missing (⇒ receives DEFAULT value)
--                         ╭───┴──╮
INSERT INTO auto_T(a,b,c,d) VALUES
  (1, 'x',  true, 10);

INSERT INTO auto_T(a,b,c,d) VALUES
  (2, 'y',  true, 40);

TABLE auto_T;

INSERT INTO auto_T(a,b,c,d) VALUES
  (5, 'x', true,  NULL),
  (4, 'y', false, 20),
  (3, 'x', false, 30)
  RETURNING k, c;
--            ↑
--     General INSERT feature:
--     Any list of expressions involving the column name of
--     the inserted rows (or * to return entire inserted rows)

TABLE auto_T;

-----------------------------------

-- Inspect all existing sequences
--
.columns

SELECT s.*
FROM   duckdb_sequences() AS s;

.rows
