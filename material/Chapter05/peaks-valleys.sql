-- Use window functions FIRST_VALUE, LAST_VALUE, NTH_VALUE to find
-- peaks and valleys in the 1D hilly landscape

-- (NB: This would be an ideal task for SQL:2016's row pattern matching)

CREATE OR REPLACE MACRO unnest_with_ordinality(xs) AS TABLE
  SELECT t.*
  FROM   unnest(list_apply(xs, (x__,i__) -> {x:x__, ordinality:i__})) AS _(t);


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


-- Move a sliding window across the landscape, record
-- descending (⭨)/ascending (⭧)/even (→) slopes in the window.

-- Context around • defines valley/peak:
--
--   valley       peak
--     ↓            ↓
-- ⭨⭨•⭧⭧    ⭧⭧•⭨⭨
-- ⭨⭨•⭧→    ⭧⭧•⭨→
-- ⭨⭨•⭧⭨    ⭧⭧•⭨⭧
-- ⭨⭨•→⭧    ⭧⭧•→⭨
--
-- ⭨→•⭧⭧    ⭧→•⭨⭨
-- ⭨→•⭧→    ⭧→•⭨→
-- ⭨→•⭧⭨    ⭧→•⭨⭧
-- ⭨→•→⭧    ⭧→•→⭨
--
-- →⭨•⭧⭧    →⭧•⭨⭨
-- →⭨•⭧→    →⭧•⭨→
-- →⭨•⭧⭨    →⭧•⭨⭧
-- →⭨•→⭧    →⭧•→⭨



-- Map a -1,0,1 signs to a "slope string" using symbols ⭧→⭨
-- on which we can pattern match (with SIMILAR TO)
CREATE OR REPLACE MACRO slope(s) AS
  map([-1,0,1,2],['⭧','→','⭨',''])[COALESCE(s,2)][1];

-- -1 ≡ ⭧
SELECT slope(-1);


WITH
-- ➊ Find slopes around point x (vicinity of -2/+2 points around x):
slopes(x, slope) AS (
  SELECT m.x,
         slope(sign(FIRST_VALUE(m.alt) OVER w - NTH_VALUE(m.alt,2) OVER w)) ||
         slope(sign(NTH_VALUE(m.alt,2) OVER w - m.alt                    )) ||
         slope(sign(m.alt                     - NTH_VALUE(m.alt,4) OVER w)) ||
         slope(sign(NTH_VALUE(m.alt,4) OVER w - LAST_VALUE(m.alt)  OVER w))
  FROM   map AS m
  WINDOW w AS (ORDER BY m.x ROWS BETWEEN 2 PRECEDING AND 2 FOLLOWING)
)
-- ➋ Use regular expression matching on the slope string
--   to find landscape features:
SELECT s.x,
       CASE WHEN s.slope SIMILAR TO '(⭨⭨|⭨→|⭧⭨|→⭨)(⭧⭧|⭧→|⭧⭨|→⭧)' THEN 'valley'
            WHEN s.slope SIMILAR TO '(⭧⭧|⭧→|⭨⭧|→⭧)(⭨⭨|⭨→|⭨⭧|→⭨)' THEN 'peak'
            ELSE '-'
       END AS feature
FROM   slopes AS s
ORDER BY s.x;
-- TABLE slopes
-- ORDER BY x;
