-- A CYK Parser in SQL (PostgreSQL)
--
-- For the CYK parsing algorithm see
--     https://en.wikipedia.org/wiki/CYK_algorithm
-- and
--     "Datafun: a Functional Datalog" (Section 3.5)
--     http://www.cs.bham.ac.uk/~krishnan/datafun.pdf

-- Relational encoding of a grammar in Chomsky reduced form.  All rules
-- are of the form (nt: non-terminal, syms: string of terminal symbols):
--
--                        nt → syms
--                        nt → nt₁ nt₂
--
-- Any context-free grammar can be turned into Chomsky reduced form
-- if it does not generate ε.

CREATE OR REPLACE MACRO unnest_with_ordinality(xs) AS TABLE
  SELECT t.*
  FROM   unnest(list_apply(xs, (x__,i__) -> {x:x__, ordinality:i__})) AS _(t);

DROP TABLE IF EXISTS grammar CASCADE;

DROP TYPE IF EXISTS nonterminal;
CREATE TYPE nonterminal AS text;

DROP TYPE IF EXISTS terminal;
CREATE TYPE terminal AS text;

CREATE TABLE grammar (lhs   nonterminal NOT NULL,
                      sym   terminal,    --   lhs → syms
                      rhs1  nonterminal, -- ⎱ lhs → rhs₁ rhs₂
                      rhs2  nonterminal, -- ⎰
                      start boolean,     --   start rule?
                      -- either the terminal or the two non-terminals are NULL
                      CHECK ((sym IS NOT NULL AND rhs1 IS NULL     AND rhs2 IS NULL)
                          OR (sym IS NULL     AND rhs1 IS NOT NULL AND rhs2 IS NOT NULL))
                     );

-- ➊ Original expression grammar (left-associative *, +; * has precedence over +)
--
-- Expr → Expr Plus Term | Term
-- Term → Term Mult Fact | Fact
-- Fact → '1'
-- Plus → '+'
-- Mult → '*'

-- ➋ After conversion into Chomsky reduced form:
--
-- Expr → Expr Sum
-- Expr → Term Prod
-- Expr → '1'
-- Term → Term Prod
-- Term → '1'
-- Sum  → Plus Term
-- Prod → Mult Fact
-- Fact → '1'
-- Plus → '+'
-- Mult → '*'

INSERT INTO grammar VALUES
  ('Expr', NULL,     'Expr', 'Sum',   true),
  ('Expr', NULL,     'Term', 'Prod',  true),
  ('Expr', '[0-9]+', NULL,   NULL,    true),
  ('Term', NULL,     'Term', 'Prod', false),
  ('Term', '[0-9]+', NULL,   NULL,   false),
  ('Sum',  NULL,     'Plus', 'Term', false),
  ('Prod', NULL,     'Mult', 'Fact', false),
  ('Fact', '[0-9]+', NULL,   NULL,   false),
  ('Plus', '[+]',    NULL,   NULL,   false),
  ('Mult', '[*×]',   NULL,   NULL,   false);

TABLE grammar;

-- Sample input string to parse
CREATE OR REPLACE MACRO input() AS '1 + 1 * 1';

-- Basic idea:
--
-- (1) Build parsing table parse(lhs,from,to).  An entry
--     (‹lhs›,‹from›,‹to›) indicates that non-terminal ‹lhs›
--     produces the substring from positions ‹from› to ‹to›
--     in the input.
--
-- (2) Recursion base case:
--     Populate parsing table with (‹lhs›,‹from›,‹to›) if rule
--     ‹lhs› → ‹syms› is in the grammar and input[‹from›:‹to›] = ‹syms›.
--
-- (3) Recursive case:
--     If (‹nt₁›,‹from₁›,‹to₁›) and (‹nt₂›,‹from₂›,‹to₂›) are in              (⁂)
--     the parsing table with ‹to₁› + 1 = ‹from₂› (i.e., the two generated
--     substrings are adjacent in the input), and there is rule
--     ‹lhs› → ‹nt₁› ‹nt₂› in the grammar, then add (‹lhs›,‹from₁›,‹to₂›)
--     to the parsing table.
--
-- (4) Post-processing:
--     If (‹lhs›,1,‹length of input›) is in the parsing table and
--     ‹lhs› is a start symbol, then parsing was successful.


WITH RECURSIVE
tokens(tok, i) AS (
  SELECT t.tok, t.i
  FROM   unnest_with_ordinality(regexp_split_to_array(input(), '\s+')) AS t(tok, i)
),
parse(iter, lhs, "from", "to") AS (
  SELECT 0 AS iter, g.lhs, t.i AS "from", t.i AS "to"
  FROM   tokens AS t, grammar AS g
  WHERE  t.tok ~ g.sym
    UNION ALL
  SELECT p.iter + 1 AS iter, p.lhs, p."from", p."to"
  FROM   (TABLE parse -- reinject already discovered parsing knowledge
            UNION
          SELECT l.iter, g.lhs, l."from", r."to"
          FROM   grammar AS g,
                 parse AS l,
                 parse AS r
          WHERE  l."to" + 1 = r."from"
          AND    (g.rhs1, g.rhs2) = (l.lhs, r.lhs)
        ) AS p
  WHERE p.iter < 4
) -- top-level WITH
--
-- TABLE tokens
-- ORDER BY i;
--
-- TABLE parse
-- ORDER BY iter, "to" - "from" DESC, "from", "to";
--
SELECT input() AS input,
       (SELECT COALESCE(bool_or(g.start), false)
        FROM   grammar g,
               parse AS p
        WHERE  p."from" = 1 AND p."to" = length(input())
        AND    g.lhs = p.lhs) AS "parses?";


-- TODO:
-- construct/visualize explicit parse tree from the final parsing table
