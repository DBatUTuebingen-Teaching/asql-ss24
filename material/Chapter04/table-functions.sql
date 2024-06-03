-- Table-generating (set-returning) SQL Functions

-----------------------------------------------------------------------
-- generate_series, range

-- 1, 3, 5, 7, 9, 11 (since 1 ⩽ i ⩽ 11)
SELECT t.i
FROM   generate_series(1,11,2) AS t(i);

-- 1, 3, 5, 7, 9 (since 1 ⩽ i < 11)
SELECT t.i
FROM   range(1,11,2) AS t(i);

-- how long will this lecture last...(in minutes)!?
SELECT t.i
FROM   range('2024-05-09 10:15:00' :: timestamp,
             '2024-05-09 11:45:00' :: timestamp,
             to_minutes(1)                        -- 1-minute intervals
            ) AS t(i);

-- access the elements of a two-dimensional list (≡ matrix)
WITH matrix(m) AS (
  VALUES ([[10,20,30],
           [40,50,60]])
)
SELECT row.r, col.c, mx.m[row.r][col.c]
FROM   matrix AS mx,
       generate_series(1, 2) AS row(r),
       generate_series(1, 3) AS col(c);



-----------------------------------------------------------------------
-- Dependent iteration (LATERAL)

-- Exception: dependent iteration OK in table-generating functions
--
SELECT t.tree, MAX(node.label) AS "largest label"
FROM   Trees AS t,
       LATERAL unnest(t.labels) AS node(label)  -- ⚠️ refers to t.labels: dependent iteration
GROUP BY t.tree;


-- Equivalent reformulation (dependent iteration → subquery in SELECT)
--
SELECT t.tree, (SELECT MAX(node.label)
                FROM   unnest(t.labels) AS node(label)) AS "largest label"
FROM   Trees AS t
GROUP BY t.tree, t.labels;


-- ⚠️ This reformulation is only possible if the subquery yields
--   a scalar result (one row, one column) only ⇒ LATERAL is more general.
--   See the example (and its somewhat awkward reformulation) below.


-----------------------------------------------------------------------

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

-- Find the three tallest two- or four-legged dinosaurs:
--
SELECT locomotion.legs, tallest.species, tallest.height
FROM   (VALUES (2), (4)) AS locomotion(legs),
       LATERAL (SELECT d.*
                FROM   dinosaurs AS d
                WHERE  d.legs = locomotion.legs
                ORDER BY d.height DESC
                LIMIT 3) AS tallest;

-- Aside: Finding the *single* tallest two- or four-legged dinosaur is a job for ARG_MAX:
--
--   SELECT d.legs, ARG_MAX(d,d.height)
--   FROM   dinosaurs AS d
--   WHERE  d.legs IS NOT NULL
--   GROUP BY d.legs;


-- Equivalent reformulation without LATERAL
--
WITH ranked_dinosaurs(species, legs, height, rank) AS (
  SELECT d1.species, d1.legs, d1.height,
         (SELECT COUNT(*)                          -- number of
          FROM   dinosaurs AS d2                   -- dinosaurs d2
          WHERE  d1.legs = d2.legs                 -- in d1's peer group
          AND    d1.height <= d2.height) AS rank   -- that are as large or larger as d1
  FROM   dinosaurs AS d1
  WHERE  d1.legs IS NOT NULL
)
SELECT d.legs, d.species, d.height
FROM   ranked_dinosaurs AS d
WHERE  d.legs IN (2,4)
AND    d.rank <= 3
ORDER BY d.legs, d.rank;
