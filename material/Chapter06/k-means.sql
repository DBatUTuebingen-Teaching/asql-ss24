-- A SQL implementation of the K-Means clustering algorithm (bag semantics)
--
-- K-Means: https://en.wikipedia.org/wiki/K-means_clustering


-- We will cluster points in 2D space
CREATE TYPE point AS struct(x float, y float);

-- Euclidean distance of two points in 2D space
CREATE OR REPLACE MACRO dist(p1,p2) AS
  sqrt((p1.x - p2.x)^2 + (p1.y - p2.y)^2);

-----------------------------------------------------------------------
-- Visualization of the K-Means clustering progress

CREATE OR REPLACE MACRO roundp(p) AS
  (round(p.x), round(p.y)) :: point;

CREATE OR REPLACE MACRO width() AS 7;
CREATE OR REPLACE MACRO height() AS 5;

-----------------------------------------------------------------------

-- # of K-Means iterations to perform in bag semantics
CREATE OR REPLACE MACRO iterations() AS 5;

-- Set of points P that we will cluster
CREATE SEQUENCE point_id;

DROP TABLE IF EXISTS points;
CREATE TABLE points (
  point  int DEFAULT nextval('point_id') PRIMARY KEY,   -- unique point ID/label
  loc    point                                          -- location of point in 2D space
);

-- Instantiate P
INSERT INTO points(loc) VALUES
   ((1.0, 1.0) :: point),
   ((2.0, 1.5) :: point),
   ((4.0, 3.0) :: point),
   ((7.0, 5.0) :: point),
   ((5.0, 3.5) :: point),
   ((5.0, 4.5) :: point),
   ((4.5, 3.5) :: point);

TABLE points;

-----------------------------------------------------------------------
-- K-Means using bag semantics (UNION ALL), ends computation after a
-- predetermined number of iterations (see macro iterations()).
--
-- k_means(‹i›, ‹p›, ‹l›, ‹𝑐›):
--   in iteration ‹i›, point ID ‹p› at location ‹l› has been assigned to cluster ID ‹c›,
--   (i.e., there exists an FD ‹p› → ‹l›).

-- CREATE TEMPORARY TABLE clustered AS
WITH RECURSIVE
sample(cluster,centroid) AS (
  SELECT ROW_NUMBER() OVER () AS cluster, p.loc AS centroid
  FROM   points AS p
  WHERE  p.point IN (5, 6)  -- choose points {5,6} as initial cluster centers (⇒ good example)
  -- USING SAMPLE 2 ROWS       -- choose 2 random points as initial cluster centers
),
k_means(iter,point,loc,cluster) AS (
  SELECT 0 AS iter, p.point, p.loc,
         (SELECT ARG_MIN(s.cluster, dist(p.loc, s.centroid))
          FROM   sample AS s) AS cluster
  FROM   points AS p
    UNION ALL
  (WITH clusters(cluster,centroid) AS (
    -- 1. Update: find new cluster centers
    SELECT k.cluster, (AVG(k.loc.x), AVG(k.loc.y)) :: point AS centroid
    FROM   k_means AS k
    GROUP BY k.cluster
   )
   -- 2. Assignment: (re-)assign points to clusters
   SELECT k.iter + 1 AS iter, k.point, k.loc,
          (SELECT ARG_MIN(c.cluster, dist(k.loc, c.centroid))
           FROM   clusters AS c) AS cluster
   FROM   k_means AS k
   WHERE  k.iter < iterations()
  )
)
SELECT k.iter, k.point, k.cluster,
       (AVG(k.loc.x) OVER cluster, AVG(k.loc.y) OVER cluster) :: point AS mean
FROM   k_means AS k
WINDOW cluster AS (PARTITION BY k.cluster)
ORDER BY k.iter, k.cluster, k.point;


-----------------------------------------------------------------------
-- Visualization of the K-Means clustering progress, expects
-- result of clustering in table clustered(iter,point,cluster,mean)
--
-- Symbols:
--  - ⚫: points before assignment to any cluster
--  - ➊: point assigned to cluster 1
--  - ①: mean of cluster 1
WITH
symbols(iter, loc, sym) AS (
  SELECT 0 AS iter, roundp(p.loc) AS loc, '⚫' AS sym
  FROM   points AS p
    UNION ALL
  SELECT c.iter, roundp(p.loc) AS loc, chr(ascii('➊') - 1 + c.cluster :: int) AS sym
  FROM   clustered AS c, points AS p
  WHERE  c.point = p.point
  AND    c.iter > 0
    UNION ALL
  SELECT c.iter, roundp(c.mean) AS loc, chr(ascii('①') - 1 + c.cluster :: int) AS sym
  FROM   clustered AS c
),
grid(iter, x, y, sym) AS (
  SELECT iter, x, y, '⋅' AS sym
  FROM   generate_series(0, iterations()) AS _(iter),
         generate_series(0, width()) AS __(x),
         generate_series(0, height()) AS ___(y)
  WHERE  (iter,x,y) NOT IN (SELECT (s.iter, s.loc.x, s.loc.y)
                            FROM   symbols AS s)
    UNION ALL
    -- if two symbols occupy the same iter/x/y spot, prefer ① over ⚫, ➊ (① < ⚫ < ➊)
  (SELECT s.iter, s.loc.x, s.loc.y, MIN(s.sym) AS sym
   FROM   symbols AS s
   GROUP BY s.iter, s.loc)
),
render(iter, y, points) AS (
  SELECT g.iter, g.y, string_agg(g.sym, '' ORDER BY g.x) AS points
  FROM   grid AS g
  GROUP BY g.iter, g.y
  ORDER BY g.iter, g.y
)
SELECT iter, points
FROM   render
ORDER BY iter, y DESC;





WITH RECURSIVE
sample(cluster,centroid) AS (
  SELECT ROW_NUMBER() OVER () AS cluster, p.loc AS centroid
  FROM   points AS p
  WHERE  p.point IN (5, 6)  -- choose points {5,6} as initial cluster centers (⇒ good example)
  -- USING SAMPLE 2 ROWS       -- choose 2 random points as initial cluster centers
),
k_means(point,loc,cluster) AS (
  SELECT p.point, p.loc,
         (SELECT ARG_MIN(s.cluster, dist(p.loc, s.centroid))
          FROM   sample AS s) AS cluster
  FROM   points AS p
    UNION
  (WITH clusters(cluster,centroid) AS (
    -- 1. Update: find new cluster centers
    SELECT k.cluster, (AVG(k.loc.x), AVG(k.loc.y)) :: point AS centroid
    FROM   k_means AS k
    GROUP BY k.cluster
   )
   -- 2. Assignment: (re-)assign points to clusters
   SELECT k.point, k.loc,
          (SELECT ARG_MIN(c.cluster, dist(k.loc, c.centroid))
           FROM   clusters AS c) AS cluster
   FROM   k_means AS k
  )
)
SELECT k.point, k.cluster,
       (AVG(k.loc.x) OVER cluster, AVG(k.loc.y) OVER cluster) :: point AS mean
FROM   k_means AS k
WINDOW cluster AS (PARTITION BY k.cluster)
ORDER BY k.cluster, k.point;
