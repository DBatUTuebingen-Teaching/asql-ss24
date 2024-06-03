-- Represent labelled forests using lists:
-- - if parents[i] = j, then j is parent node of node i,
-- - if labels[i] = ℓ, then ℓ is the label of node i.

DROP TABLE IF EXISTS Trees;

CREATE TABLE Trees (tree    int PRIMARY KEY,
                    parents int[],
                    labels  text[]);

--      t₁                  t₂                     t₃
--
--   ¹     ᵃ           ⁶     ᵍ           ¹ ³     ᵃ ╷ᵈ
-- ² ⁵  ᵇ ᶜ        ⁴ ⁷  ᵇ ᶜ                  ╵
--      ╵        ¹ ⁵  ᵈ ᵉ          ² ⁴ ⁵     ᵇ ᶜ ᵉ
-- ³ ⁴⁶   ᵈ ᵉᶠ              
--                    ² ³    ᶠ ᵃ

INSERT INTO Trees(tree, parents, labels) VALUES
  (1, [NULL,1,2,2,1,5],   ['a','b','d','e','c','f']),
  (2, [4,1,1,6,4,NULL,6], ['d','f','a','b','e','g','c']),
  (3, [NULL,1,NULL,1,3],  string_split('a;b;d;c;e',';'));

TABLE trees;

-- Consistency: length of parents[] and labels[] match for all trees?
--
SELECT bool_and(len(t.parents) = len(t.labels))
FROM   Trees AS t;


-- Which trees (and nodes) carry an 'f' label?
--
SELECT t.tree, list_position(t.labels, 'f') AS "f node"
FROM   Trees AS t
WHERE  'f' = ANY(t.labels);


-- Advanced list processing (Haskell-inspired)
--
SELECT list_transform([1,2,3,4,5,6], x -> x*x);

SELECT list_reduce(['x₁','x₂','x₃','x₄','x₅'], (a,x) -> '('||a||' ⊗ '||x||')');

SELECT list_transform(string_split('abcdef', ''), (c,i) -> c || i);


-- Advanced list processing (APL-inspired)
--
SELECT list_grade_up(['f','a','c','d','b','e']);
-- = [2, 5, 3, 4, 6, 1]
--    ↑
--   "in a sorted list, the element at index 2 ('a') should be here (at index 1)"

SELECT list_grade_up(list_grade_up(['f','a','c','d','b','e']));
-- = [6, 1, 3, 4, 2, 5]
--    ↑
--   "in a sorted list, this element ('f') will be at index 6"

SELECT list_select(['f','a','c','d','b','e'], list_grade_up(['f','a','c','d','b','e']))
         =
       list_sort(['f','a','c','d','b','e']);


-- Find the label of the root node(s)
--
SELECT t.tree, list_where(t.labels, list_transform(t.parents, p -> p is NULL)) AS roots
FROM   Trees AS t;


-- Which trees actually are forests (collection of trees with more
-- than one root)?
--
SELECT t.tree AS forest
FROM   Trees AS t
WHERE  len(list_where(t.labels, list_transform(t.parents, p -> p is NULL))) > 1;


-- Advanced List processing (Haskell/Python-inspired list comprehensions)
--
SELECT [x*x for x in [1,2,3,4,5,6] if x % 2 <> 0];



-----------------------------------------------------------------------
-- DuckDB is an RDBMS, not a list processing system

-- "Shoelace formula" (https://en.wikipedia.org/wiki/Shoelace_formula)
-- for the area of a polygon given its vertices:


DROP TYPE IF EXISTS point;
CREATE TYPE point AS row(x int, y int);

DROP TABLE IF EXISTS polygon;
CREATE TABLE polygon(i int, x int, y int);
INSERT INTO polygon(i,x,y) VALUES
	(1,1,6),
	(2,1,1),
	(3,7,1),
	(4,5,4),
	(5,7,6);
-- INSERT INTO polygon(i,x,y)
--   SELECT i, (random() * 1000) :: int AS x, (random() * 1000) :: int AS y
--   FROM   generate_series(1,50000000) AS _(i);

.timer on

SELECT SUM(shoe.lace) / 2 AS area
FROM   (SELECT p.x * LEAD(p.y,1,p1.y) OVER w - p.y * LEAD(p.x,1,p1.x) OVER w AS lace
        FROM   polygon AS p, polygon AS p1
        WHERE  p1.i = 1
        WINDOW w AS (ORDER BY p.i)) AS shoe;

SELECT list_sum(
         list_transform(
           list_zip(poly.vertices, poly.vertices[2:] || [poly.vertices[1]]),
           p -> p[1].x * p[2].y - p[1].y * p[2].x)) / 2	AS area
FROM   (SELECT list((p.x, p.y) :: point ORDER BY p.i) AS vertices
        FROM   polygon AS p) AS poly;



-----------------------------------------------------------------------
-- unnest / list (aggregate)
--

-- ⚠️ A temporary replacement for the idiom unnest(xs) WITH ORDINALITY
--    that is not yet supported in DuckDB (PR in progress):
CREATE OR REPLACE MACRO unnest_with_ordinality(xs) AS TABLE
  SELECT t.*
  FROM   unnest(list_apply(xs, (x__,i__) -> {x:x__, ordinality:i__})) AS _(t);


SELECT t.*
FROM   unnest_with_ordinality(['x₁','x₂','x₃']) AS t(elem,idx);

--                              try: DESC
--                                 ↓
SELECT list(t.elem ORDER BY t.idx ASC) AS xs
FROM   (VALUES ('x₁',1),
               ('x₂',2),
               ('x₃',3)) AS t(elem,idx);


-- Split string into individual words/characters, together with their index
--
SELECT words.pos, words.word
FROM   unnest_with_ordinality(
        string_split('Luke, I am Your Father', ' ')) AS words(word, pos);


-- Split string into whitespace-separated words
--
SELECT words.*
FROM   unnest_with_ordinality(
        regexp_split_to_array('Luke, I am Your Father', '\s+')) AS words(word,pos);
--                                                        ↑
--                           any white space character, alternatively: [[:space:]]



-- Transform all labels to uppercase:
--
SELECT t.tree,
       list(node.parent      ORDER BY node.idx) AS parents,
       list(upper(label.lbl) ORDER BY node.idx) AS labels
FROM   Trees AS t,
       unnest_with_ordinality(t.parents) AS node(parent,idx),
       unnest_with_ordinality(t.labels)  AS label(lbl,idx)
WHERE  node.idx = label.idx
GROUP BY t.tree;


-- Find the parents of all nodes with label 'c'
--
SELECT t.tree, t.parents[label.idx] AS "parent of c"
FROM   Trees AS t,
       unnest_with_ordinality(t.labels) AS label(lbl,idx)
WHERE  label.lbl = 'c';


-- Find the forests among the trees:
--
SELECT t.tree                            -- SELECT t.*
FROM   Trees AS t,
       unnest(t.parents) AS node(parent)
WHERE  node.parent IS NULL
GROUP BY t.tree                          -- GROUP BY ALL
HAVING COUNT(*) > 1; -- true forests have more than one root node


-- Problem:
--
-- Which nodes are on the path from node labeled 'f' to the root?
--
-- (↯☠☹⛈)
--
-- Would need to repeatedly peek into parents[] list until we hit
-- the root node.  But how long will the path be?
--
-- SOMETHING'S STILL MISSING. (⇒ Later)

-----------------------------------------------------------------------
-- Nested Structs and Lists vs. JSON

-- A color in the RGB space
DROP TYPE IF EXISTS rgb;
CREATE TYPE rgb AS row(r int, g int, b int);
-- A named RGB color
DROP TYPE IF EXISTS color;
CREATE TYPE color AS row(color text, rgb rgb);

-- Convert decimal RGB values into #rrggbb hex format
SELECT list({'color': t.c.color,
             'hex': format('#{:x}{:x}{:x}', t.c.rgb.r, t.c.rgb.g, t.c.rgb.b)}
           ) :: json AS colors
--           ↑
--       cast from SQL list of structs to JSON array of objects
FROM   unnest(json('[{"color": "lime",   "rgb": {"r":153, "g":255, "b":251} },
                     {"color": "barbie", "rgb": {"r":255, "g":102, "b":255} },
                     {"color": "black",  "rgb": {"r":"0,   "g":0,   "b":0  } }
                    ]') :: color[]) AS t(c);
--                      ↑
--                  cast from JSON array of object to SQL list of color structs
--
-- ⚠️ replace any JSON object key or any int value with "x"
-- to observe how the cast to SQL fails


-----------------------------------------------------------------------
-- Key/Values Maps

--  Map DNS top-level domains to their respective country flags (buggy)
WITH countries(flags) AS (
  VALUES (map(['de','pl','gb'], ['🇩🇪','🇮🇩','🇬🇧']))
)
SELECT c.flags[tld.code]
FROM   countries AS c,
       (VALUES ('gb'),
               ('pl'),
               ('it')) AS tld(code);


--  Use map_concat to fix/update the tld→flag mapping
WITH countries(flags) AS (
  VALUES (map(['de','pl','gb'], ['🇩🇪','🇮🇩','🇬🇧']))
)
SELECT map_concat(c.flags, map {'it':'🇮🇹', 'pl':'🇵🇱'})[tld.code]
--                               ↑          ↑
--                           adds key     overwrites key
FROM   countries AS c,
      (VALUES ('gb'),
              ('pl'),
              ('it')) AS tld(code);


-- See https://duckdb.org/docs/sql/functions/nested
