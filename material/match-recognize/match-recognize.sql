-- executable on oracle
-- try out oracle in docker:  https://container-registry.oracle.com/ords/ocr/ba/database/enterprise

SET linesize 600
SET WRAP OFF

DROP TABLE map;
CREATE TABLE map(x NUMBER, alt NUMBER);

INSERT ALL
  INTO map VALUES (0 , 406)
  INTO map VALUES (7 , 404)
  INTO map VALUES (18, 404)
  INTO map VALUES (22, 401)
  INTO map VALUES (28, 403)
  INTO map VALUES (31, 403)
  INTO map VALUES (35, 407)
  INTO map VALUES (44, 402)
  INTO map VALUES (50, 402)
  INTO map VALUES (56, 403)
  INTO map VALUES (62, 402)
SELECT 1 FROM dual;

-- this query identifies all valleys in the data
-- for example features like this:
--   \_
--     \  _/
--      \/
SELECT *
FROM   map MATCH_RECOGNIZE (
  ORDER BY x
  MEASURES MATCH_NUMBER()      AS feature,
           PREV(FIRST(DOWN.x)) AS strt,
           LAST(UP.x)          AS term
  ONE ROW PER MATCH
  AFTER MATCH SKIP PAST LAST ROW
  PATTERN( DOWN (DOWN|EVEN)* (EVEN|UP)* UP )
  DEFINE   UP   AS UP.alt   > PREV(UP.alt),
           DOWN AS DOWN.alt < PREV(DOWN.alt),
           EVEN AS EVEN.alt = PREV(EVEN.alt)
) mr;
