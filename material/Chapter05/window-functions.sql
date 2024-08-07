-- Window functions

-----------------------------------------------------------------------
-- Demonstrate the semantics of window frames

DROP TABLE IF EXISTS W;
CREATE TABLE W (
  row text PRIMARY KEY,
  a   int,
  b   text
);

INSERT INTO W(row, a, b) VALUES
  ('ϱ1', 1, '⚫'),
  ('ϱ2', 2, '⚪'),
  ('ϱ3', 3, '⚪'),
  ('ϱ4', 3, '⚫'),
  ('ϱ5', 3, '⚪'),
  ('ϱ6', 4, '⚪'),
  ('ϱ7', 6, '⚫'),
  ('ϱ8', 6, '⚫'),
  ('ϱ9', 7, '⚪');

TABLE W
ORDER BY row;

-- ➊ OVER (): for each current row, ALL rows are inside the frame
--
SELECT w.row                AS "current row",
       COUNT(*)    OVER win AS "frame size",
       list(w.row) OVER win AS "rows in frame"
FROM   W AS w
WINDOW win AS ();


-- Attaches aggregates to all rows
--
SELECT w.row                        AS "current row",
       w.a,
       SUM(w.a)            OVER win AS "∑ a",
       MAX(w.a)            OVER win AS "max(a)",
       bool_and(w.b = '⚫') OVER win AS "∀ b=⚫"
FROM   W AS w
WINDOW win AS ();


-- ➋ OVER (ORDER BY w.a) ≡
--   OVER (ORDER BY w.a RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
--                        ↑
--     all rows with identical w.a value are in the peer group of the CURRENT ROW
--
SELECT w.row                AS "current row",
       w.a,
       COUNT(*)    OVER win AS "frame size",
       list(w.row) OVER win AS "rows in frame"
FROM   W AS w
WINDOW win AS (ORDER BY w.a)
ORDER BY w.a, w.row;  --  ← for presentation only, does NOT affect window frames



-- ➌ OVER (ORDER BY w.a ROWS UNBOUNDED PRECEDING AND CURRENT ROW)
--                        ↑
--     the CURRENT ROW is the single current row only (cf. ➋)
--
SELECT w.row                AS "current row",
       w.a,
       COUNT(*)    OVER win AS "frame size",
       list(w.row) OVER win AS "rows in frame"
FROM   W AS w
WINDOW win AS (ORDER BY w.a ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
ORDER BY w.a, w.row;


-- Compute running (∑ a) sum
--
SELECT w.row             AS "current row",
       w.a,
       SUM(w.a) OVER win AS "∑ a (so far)"
FROM   W AS w
WINDOW win AS (ORDER BY w.a ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
ORDER BY w.a, w.row;



-- ➍ OVER (ORDER BY w.a ROWS BETWEEN 1 PRECEDING AND 2 FOLLOWING)
--   ("sliding window",
--     may contains less than 4 = 1 (PREC) + 1 (CURR) + 2 (FOLL) rows on the edges)
--
SELECT w.row                AS "current row",
       w.a,
       COUNT(*)    OVER win AS "frame size",
       list(w.row) OVER win AS "rows in frame"
FROM   W AS w
WINDOW win AS (ORDER BY w.a ROWS BETWEEN 1 PRECEDING AND 2 FOLLOWING)
ORDER BY w.a;


-- "Smooth" the values in column a using a sliding window of size 3:
--
SELECT w.row                             AS "current row",
       w.a,
       AVG(w.a) OVER win :: numeric(4,2) AS "smoothed a"
FROM   W AS w
WINDOW win AS (ORDER BY w.a ROWS BETWEEN 1 PRECEDING AND 1 FOLLOWING)
ORDER BY w.a;



-- ➎ Frame exclusion (EXCLUDE ...)

SELECT w.row                     AS "current row",
       w.a,
       list(w.row) OVER win      AS "rows in frame",
       list(w.row) OVER win1 AS "EXCLUDE CURRENT ROW",
       list(w.row) OVER win2 AS "EXCLUDE GROUP",
       list(w.row) OVER win3 AS "EXCLUDE TIES"
FROM   W AS w
WINDOW win  AS (ORDER BY w.a RANGE BETWEEN 1 PRECEDING AND CURRENT ROW), -- EXCLUDE NO OTHERS
       win1 AS (ORDER BY w.a RANGE BETWEEN 1 PRECEDING AND CURRENT ROW EXCLUDE CURRENT ROW),
       win2 AS (ORDER BY w.a RANGE BETWEEN 1 PRECEDING AND CURRENT ROW EXCLUDE GROUP),
       win3 AS (ORDER BY w.a RANGE BETWEEN 1 PRECEDING AND CURRENT ROW EXCLUDE TIES)
ORDER BY w.a;



-----------------------------------------------------------------------
-- What is the chance of fine weather on weekends?


-- Daily weather sensor readings
--
DROP TABLE IF EXISTS sensors;
CREATE TABLE sensors (
  day     int PRIMARY KEY, -- day of month
  weekday text,            -- day of week (Mon...Sun)
  temp    float,           -- temperature in °C
  rain    float);          -- rainfall in ml

INSERT INTO sensors(day, weekday, temp, rain) VALUES
  ( 1, 'Thu', 13,   0),
  ( 2, 'Fri', 10, 800),
  ( 3, 'Sat', 12, 300),
  ( 4, 'Sun', 16, 100),
  ( 5, 'Mon', 20, 400),
  ( 6, 'Tue', 20,  80),
  ( 7, 'Wed', 18, 500),
  ( 8, 'Thu', 14,   0),
  ( 9, 'Fri', 10,   0),
  (10, 'Sat', 12, 500),
  (11, 'Sun', 14, 300),
  (12, 'Mon', 14, 800),
  (13, 'Tue', 16,   0),
  (14, 'Wed', 15,   0),
  (15, 'Thu', 18, 100),
  (16, 'Fri', 17, 100),
  (17, 'Sat', 15,   0),
  (18, 'Sun', 16, 300),
  (19, 'Mon', 16, 400),
  (20, 'Tue', 19, 200),
  (21, 'Wed', 19, 100),
  (22, 'Thu', 18,   0),
  (23, 'Fri', 17,   0),
  (24, 'Sat', 16, 200);

TABLE sensors
ORDER BY day;


WITH
-- ➊ Collect weather data for each day (and two days prior)
three_day_sensors(day, weekday, temp, rain) AS (
  SELECT s.day, s.weekday,
         MIN(s.temp) OVER three_days AS temp,
         SUM(s.rain) OVER three_days AS rain
  FROM   sensors AS s
  WINDOW three_days AS (ORDER BY s.day ROWS BETWEEN 2 PRECEDING AND CURRENT ROW)
),
-- ➋ Derive sunny/gloomy conditions from aggregated sensor readings
weather(day, weekday, condition) AS (
  SELECT s.day, s.weekday,
         CASE WHEN s.temp >= 15 and s.rain <= 600
              THEN '☀'
              ELSE '☔'
         END AS condition
  FROM   three_day_sensors AS s
)
-- ➌ Calculate chance of fine weather on a weekday/weekend
SELECT w.weekday IN ('Sat', 'Sun') AS "weekend?",
      (COUNT(*) FILTER (WHERE w.condition = '☀') * 100.0 /
       COUNT(*)) :: int  AS "% fine"
FROM   weather AS w
GROUP BY "weekend?";


-----------------------------------------------------------------------
-- PARTITION BY


-- UNBOUNDED PRECEDING (and FOLLOWING) respect partition boundaries
--
SELECT w.row                AS "current row",
       w.a,
       w.b                  AS "partition",
       COUNT(*)    OVER win AS "frame size",
       list(w.row) OVER win AS "rows in frame"
FROM   W AS w
WINDOW win AS (PARTITION BY w.b ORDER BY w.a ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
ORDER BY w.b, w.a, w.row;

-- Frames do not cross partitions
--
SELECT w.row                AS "current row",
       w.a,
       w.b                  AS "partition",
       COUNT(*)    OVER win AS "frame size",
       list(w.row) OVER win AS "rows in frame"
FROM   W AS w
WINDOW win AS (PARTITION BY w.b ORDER BY w.a ROWS BETWEEN 1 PRECEDING AND 2 FOLLOWING)
ORDER BY w.b, w.a, w.row;


-- Compute running (∑ a) sum in each partition
--
SELECT w.row             AS "current row",
       w.a,
       w.b               AS "partition",
       SUM(w.a) OVER win AS "∑ a (so far)"
FROM   W AS w
WINDOW win AS (PARTITION BY w.b ORDER BY w.a ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
ORDER BY w.b, w.a, w.row;


-----------------------------------------------------------------------
-- What's Visible in a Hilly Landscape?

-- See files visible.sql, visible-left-right.sql


-----------------------------------------------------------------------
-- Scan Quiz: What is computed here?

CREATE OR REPLACE MACRO unnest_with_ordinality(xs) AS TABLE
  SELECT t.*
  FROM   unnest(list_apply(xs, (x__,i__) -> {x:x__, ordinality:i__})) AS _(t);


CREATE OR REPLACE MACRO xs() AS '((b*2)-4×a×c)*0.5';

SELECT inp.pos, inp.c,
       SUM([0,1,-1][p.oc]) OVER (ORDER BY inp.pos) AS d
FROM   unnest_with_ordinality(string_split(xs(), '')) AS inp(c,pos),
       LATERAL (VALUES (list_position(['(',')'], inp.c) + 1)) AS p(oc)
ORDER BY inp.pos;


-----------------------------------------------------------------------
-- LAG/LEAD


SELECT w.row                             AS "current row",
       w.a                               AS a,
       w.b                               AS "partition",
       LAG (w.row, 1, 'no row') OVER win AS "lag",
       LEAD(w.row, 1, 'no row') OVER win AS "lead"
FROM   W AS w
WINDOW win AS (PARTITION BY w.b ORDER BY w.a)
ORDER BY w.b, w.a;



-- The hill height map
DROP TABLE IF EXISTS map;
CREATE TABLE map (
  x   integer NOT NULL PRIMARY KEY,  -- location
  alt integer NOT NULL               -- altidude at location
);

INSERT INTO map(x, alt) VALUES
  (  0, 200),
  ( 10, 200),
  ( 20, 200),
  ( 30, 300),
  ( 40, 400),
  ( 50, 400),
  ( 60, 400),
  ( 70, 200),
  ( 80, 400),
  ( 90, 700),
  (100, 800),
  (110, 700),
  (120, 500);

SELECT m.x, m.alt, bar(m.alt,0,1000,20)
FROM   map AS m;


SELECT m.x, m.alt,
       CASE sign(LEAD(m.alt, 1) OVER rightwards - m.alt)
            WHEN -1 THEN '⭨'
            WHEN  0 THEN '⭢'
            WHEN  1 THEN '⭧'
                    ELSE '?'
            END AS climb,
       LEAD(m.alt, 1) OVER rightwards - m.alt AS "by [m]"
FROM   map AS m
WINDOW rightwards AS (ORDER BY m.x);

-----------------------------------------------------------------------
-- FIRST_VALUE, LAST_VALUE, NTH_VALUE


SELECT w."row"                       AS "current row",
       array_agg(w."row")   OVER win AS "rows in frame",
       FIRST_VALUE(w."row") OVER win AS "first row",
       LAST_VALUE(w."row")  OVER win AS "last row",
       NTH_VALUE(w."row",2) OVER win AS "second row"
FROM   W AS w
WINDOW win AS (ORDER BY w.a ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING)
ORDER BY w.a, w.row;



-- Find  features (peaks, valleys) in the hilly landscape

-- See file peaks-valleys.sql


-----------------------------------------------------------------------
-- ROW_NUMBER, RANK, DENSE_RANK


SELECT w."row"               AS "current row",
       w.a,
       ROW_NUMBER() OVER win AS "ROW_NUMBER",
       DENSE_RANK() OVER win AS "DENSE_RANK",
       RANK()       OVER win AS "RANK"
FROM   W AS w
WINDOW win AS (ORDER BY w.a)
ORDER BY w.a;



-- Numbering/ranking is performed inside each partition
--
SELECT w."row"               AS "current row",
       w.a,
       w.b,
       ROW_NUMBER() OVER win AS "ROW_NUMBER",
       DENSE_RANK() OVER win AS "DENSE_RANK",
       RANK()       OVER win AS "RANK"
FROM   W AS w
WINDOW win AS (PARTITION BY w.b ORDER BY w.a)
ORDER BY w.b, w.a;



-- Once more: Which are the three tallest two- and four-legged dinosaurs?
-- (we need a subquery: window functions may not be place in the WHERE clause)
--
-- Input table dinosaurs(species, length, height, legs)
DROP TABLE IF EXISTS dinosaurs;
CREATE TABLE dinosaurs (species text, height float, length float, legs int);

INSERT INTO dinosaurs(species, height, length, legs) VALUES
  ('Ceratosaurus',      4.0,   6.1,  2),
  ('Deinonychus',       1.5,   2.7,  2),
  ('Microvenator',      0.8,   1.2,  2),
  ('Plateosaurus',      2.1,   7.9,  2),
  ('Spinosaurus',       2.4,  12.2,  2),
  ('Tyrannosaurus',     7.0,  15.2,  2),
  ('Velociraptor',      0.6,   1.8,  2),
  ('Apatosaurus',       2.2,  22.9,  4),
  ('Brachiosaurus',     7.6,  30.5,  4),
  ('Diplodocus',        3.6,  27.1,  4),
  ('Supersaurus',      10.0,  30.5,  4),
  ('Albertosaurus',     4.6,   9.1,  NULL),  -- Bi-/quadropedality is
  ('Argentinosaurus',  10.7,  36.6,  NULL),  -- unknown for these species.
  ('Compsognathus',     0.6,   0.9,  NULL),  --
  ('Gallimimus',        2.4,   5.5,  NULL),  -- Try to infer pedality from
  ('Mamenchisaurus',    5.3,  21.0,  NULL),  -- their ratio of body height
  ('Oviraptor',         0.9,   1.5,  NULL),  -- to length.
  ('Ultrasaurus',       8.1,  30.5,  NULL);  --

SELECT tallest.legs, tallest.species, tallest.height
FROM   (SELECT d.legs, d.species, d.height,
               RANK() OVER (PARTITION BY d.legs
                            ORDER BY d.height DESC) AS rank
        FROM   dinosaurs AS d
        WHERE  d.legs IS NOT NULL) AS tallest(legs,species,height,rank)
WHERE  tallest.rank <= 3
ORDER BY tallest.legs, tallest.height;



-- Can simulate ranking through counting:
--
SELECT w."row"                          AS "current row",
       w.a,
       -- ROW_NUMBER()
       ROW_NUMBER() OVER win            AS "ROW_NUMBER",
       COUNT(*) OVER (win ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW)
                                        AS "like ROW_NUMBER",
       -- RANK()
       RANK() OVER win                  AS "RANK",
                        --            size of the peer group of the current row
                        -- ──────────────────────────────────────────────────────────
       COUNT(*) OVER win - COUNT(*) OVER (win RANGE BETWEEN CURRENT ROW AND CURRENT ROW) + 1
                                        AS "like RANK",
       -- DENSE_RANK()
       DENSE_RANK() OVER win            AS "DENSE_RANK",
       COUNT(DISTINCT w.a) OVER win     AS "like DENSE_RANK"
FROM   W AS w
WINDOW win AS (ORDER BY w.a)
ORDER BY w.a;


-----------------------------------------------------------------------
-- PERCENT_RANK, CUME_DIST, NTILE

SELECT w."row"                 AS "current row",
       w.a,
       PERCENT_RANK() OVER win AS "PERCENT_RANK",
       CUME_DIST()    OVER win AS "CUME_DIST",
       NTILE(3)       OVER win AS "NTILE(3)"
FROM   W AS w
WINDOW win AS (ORDER BY w.a)
ORDER BY w.a;


-- These window functions are syntactic sugar,
-- we can simulate them as follows:
--
-- PERCENT_RANK() OVER w = (RANK() OVER w - 1) / (COUNT(*) OVER () - 1)
-- CUME_DIST() OVER w    = COUNT(*) OVER w / COUNT(*) OVER ()
-- NTILE(‹n›)            = ⌈COUNT(*) OVER (w ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) / ‹n›⌉

SELECT w."row"                          AS "current row",
       w.a,
       -- PERCENT_RANK()
       PERCENT_RANK() OVER win          AS "PERCENT_RANK",
       (RANK() OVER win - 1) :: float / (COUNT(*) OVER () - 1)
                                        AS "like PERCENT_RANK",
       -- CUME_DIST()
       CUME_DIST() OVER win             AS "CUME_DIST",
       COUNT(*) OVER win :: float / COUNT(*) OVER ()
                                        AS "like CUME_DIST()",
       -- NTILE()
       NTILE(3) OVER win                AS "NTILE(3)",
       ceil(COUNT(*) OVER (win ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW) :: float / 3)
                                        AS "like NTILE(3)"
FROM   W AS w
WINDOW win AS (ORDER BY w.a)
ORDER BY w.a;


-----------------------------------------------------------------------
-- Use NTILE(n) to linearly approximate a data set:
-- reduce data set to n segments, in each segment [t₀,t₁] approximate
-- the data set by a linear function m × t + b, t ∊ [t₀,t₁]

-- Table (t, f(t)) of measurements at time t
--
DROP TABLE IF EXISTS experiment;
CREATE TABLE experiment (
  t int PRIMARY KEY,  -- time t of measurement
  f float             -- f(t)
);

-- # of experimental measurements
CREATE OR REPLACE MACRO N() AS 100;
-- Desired # of segments after reduction
CREATE OR REPLACE MACRO segments() AS 5;

INSERT INTO experiment(t, f)
  SELECT t, random() * 40 AS f
  FROM   range(N()) AS _(t);

TABLE experiment;

WITH
-- Tag each point in the data set with its segment #
tiles(tile, t, f) AS (
  SELECT NTILE(segments()) OVER (ORDER BY e.t) AS tile, e.t, e.f
  FROM   experiment AS e
),
-- In each segment, find the segment boundaries [t0,t1] and the
-- measurements f(t₀), f(t₁)
segments(t0, t1, f0, f1) AS (
  SELECT DISTINCT ON (t.tile)
         FIRST_VALUE(t.t) OVER segment AS t0, LAST_VALUE(t.t) OVER segment AS t1,
         FIRST_VALUE(t.f) OVER segment AS f0, LAST_VALUE(t.f) OVER segment AS f1
  FROM   tiles AS t
  WINDOW segment AS (PARTITION BY t.tile ORDER BY t.t ROWS BETWEEN UNBOUNDED PRECEDING
                                                               AND UNBOUNDED FOLLOWING)
)
-- For each segment, output segment boundaries t₀, t₁, and
-- parameters m,b of linear approximation m × t + b
SELECT s.t0, s.t1, (s.f1 - s.f0) / (s.t1 - s.t0) AS m, s.f0 AS b
FROM   segments AS s
ORDER BY s.t0;
-- TABLE tiles
-- ORDER BY t;
-- TABLE segments
-- ORDER BY t0;
