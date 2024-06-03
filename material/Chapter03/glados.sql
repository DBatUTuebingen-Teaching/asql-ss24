-----------------------------------------------------------------------
-- Store and play GLaDOS voice lines from Portal 1 & 2

DROP TYPE IF EXISTS edition;
CREATE TYPE edition AS ENUM ('Portal 1', 'Portal 2');

DROP TABLE IF EXISTS glados;
CREATE TABLE glados (portal edition,         -- ⎰ meta data,
                     line   text,            -- ⎱ properties
                     voice  blob,            -- BLOB data
  PRIMARY KEY (portal, line));

CREATE MACRO blob_path() AS '/Users/grust/AdvancedSQL/slides/Week03/live/GLaDOS/';

-- Builtin function read_blob(‹glob›) reads files matching pattern ‹glob›
-- and returns rows with columns
--  - filename      :: text
--  - content       :: blob
--  - size          :: int
--  - last_modified :: timestamp
--
SELECT b.*
FROM   read_blob(blob_path() || '*.wav') AS b;

-- Load all Portal *.wav files
INSERT INTO glados(portal, line, voice)
	SELECT string_split(parse_filename(wav.filename, true, '/'), '-')[1] :: edition AS portal,
	       string_split(parse_filename(wav.filename, true, '/'), '-')[2]            AS line,
	       wav.content                                                              AS voice
	FROM   read_blob(blob_path() || '*.wav') AS wav;

TABLE glados;

-- Dump table contents, dump (prefix of) base64 encoding of BLOB for table output
SELECT g.portal, g.line,
       left(base64(g.voice), 30) AS voice
FROM   glados AS g;

-- Extract selected GLaDOS voice line, play the resulting audio file
-- (on macOS/SoX) via
--
--   $ base64 -d /tmp/GlaDOS-says.base64 | play -q -
--

COPY (
  SELECT base64(g.voice) AS content
  FROM   glados AS g
  WHERE  g.line LIKE '%button%'
) TO '/tmp/GlaDOS-says.base64' (format csv, header false);
