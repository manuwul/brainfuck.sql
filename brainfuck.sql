-- ======================================
--                 CONFIG
-- ======================================
PRAGMA recursive_triggers = ON;
PRAGMA recursive_limit = 1000;
PRAGMA temp_store = 2;
DROP TABLE IF EXISTS tape;
DROP TABLE IF EXISTS io;
DROP TABLE IF EXISTS loops;
DROP TABLE IF EXISTS inter;

-- ======================================
--                 TAPE
-- ======================================
CREATE TABLE tape (
	cell TINYINT DEFAULT 0
);
WITH RECURSIVE count(i) AS (
	SELECT 1
	UNION ALL
	SELECT i + 1 FROM count WHERE i < 30000
)
INSERT INTO tape (cell) SELECT 0 FROM count;

-- ======================================
--                 IO
-- ======================================
CREATE TABLE io (
	caret BIGINT DEFAULT  1,
	input  TEXT  DEFAULT '',
	output TEXT  DEFAULT '',
	repeat TEXT  DEFAULT ''
);
INSERT INTO io DEFAULT VALUES;

-- ======================================
--                LOOPS
-- ======================================
CREATE TABLE loops (
	left  BIGINT DEFAULT 0,
	right BIGINT DEFAULT 0
);

-- ======================================
--              INTERPRETER
-- ======================================
CREATE TABLE inter (
	program TEXT DEFAULT '',
	program_opt TEXT DEFAULT '',
	program_ptr BIGINT DEFAULT 1,
	loops_checked BOOLEAN DEFAULT FALSE,
	optimized BOOLEAN DEFAULT FALSE
);
INSERT INTO inter DEFAULT VALUES;

-- ======================================
--               OPTIMIZING
-- ======================================
CREATE TRIGGER optimize
AFTER UPDATE ON inter
WHEN NOT NEW.optimized BEGIN
	UPDATE inter SET optimized = TRUE, program_opt = (
	WITH RECURSIVE
	get_combos(pos, ch, combo) AS (
		SELECT 1, SUBSTR(NEW.program, 1, 1), 0
		UNION ALL
		SELECT
			pos + 1,
			SUBSTR(NEW.program, pos + 1, 1),
			combo + CASE SUBSTR(NEW.program, pos + 1, 1)
				WHEN '[' THEN 1
				WHEN ']' THEN 1
				WHEN ch THEN 0
				ELSE 1
			END
		FROM get_combos
		WHERE pos < LENGTH(NEW.program)
	),
	groups AS (
		SELECT ch, COUNT(*) as cnt FROM get_combos GROUP BY combo
	)
	SELECT GROUP_CONCAT(
		CASE 
			WHEN ch IN ('[', ']') THEN '' 
			ELSE cnt 
		END || ch, '') FROM groups);
END;

-- ======================================
--            LOOPS CHECKING
-- ======================================
CREATE TRIGGER check_loops
AFTER UPDATE ON inter
WHEN NEW.optimized AND NOT NEW.loops_checked BEGIN
	INSERT INTO loops (left, right)
	WITH RECURSIVE
	get_depths(pos, ch, depth) AS (
		SELECT 1, SUBSTR(NEW.program_opt, 1, 1), 0
		UNION ALL
		SELECT
			pos + 1,
			SUBSTR(NEW.program_opt, pos + 1, 1),
			depth + CASE ch
				WHEN ']' THEN -1
				ELSE CASE SUBSTR(NEW.program_opt, pos + 1, 1)
					WHEN '[' THEN 1
					ELSE 0
				END
			END
		FROM get_depths
		WHERE pos < LENGTH(NEW.program_opt)
	),
	lefts AS (
		SELECT pos, depth FROM get_depths WHERE ch = '['
	),
	rights AS (
		SELECT pos, depth FROM get_depths WHERE ch = ']'
	)
	SELECT lefts.pos, rights.pos
	FROM lefts
	JOIN rights ON lefts.depth = rights.depth AND lefts.pos < rights.pos
	WHERE NOT EXISTS (
		SELECT 1 FROM rights rights2
		WHERE lefts.depth = rights2.depth 
			AND lefts.pos < rights2.pos 
			AND rights2.pos < rights.pos
	);
	UPDATE inter SET loops_checked = TRUE;
END;

-- ======================================
--               INTERPRETING
-- ======================================
CREATE TRIGGER step
AFTER UPDATE ON inter
WHEN NEW.optimized AND NEW.loops_checked AND NEW.program_ptr < LENGTH(NEW.program_opt) BEGIN
	UPDATE io SET repeat = CAST(CAST(SUBSTR(NEW.program_opt, NEW.program_ptr) AS BIGINT) AS TEXT);

	UPDATE io SET caret = CASE SUBSTR(NEW.program_opt, NEW.program_ptr + LENGTH(repeat), 1)
		WHEN '<' THEN MAX(caret - (SELECT CAST(repeat AS BIGINT) FROM io), 0)
		WHEN '>' THEN MIN(caret + (SELECT CAST(repeat AS BIGINT) FROM io), 30000)
		ELSE caret
	END;

	UPDATE tape SET cell = CASE SUBSTR(NEW.program_opt, NEW.program_ptr + LENGTH((SELECT repeat FROM io)), 1)
		WHEN '+' THEN (cell + (SELECT CAST(repeat AS BIGINT) FROM io)) % 256
		WHEN '-' THEN (cell + 256 - ((SELECT CAST(repeat AS BIGINT) FROM io) % 256)) % 256
		WHEN ',' THEN (
			SELECT COALESCE(
				UNICODE(
					SUBSTR(input, CAST(repeat AS BIGINT), 1)
				), 0) 
			FROM io)
		ELSE cell
	END
	WHERE rowid = (SELECT caret FROM io);
	UPDATE io SET input = SUBSTR(input, CAST(repeat AS BIGINT) + 1);

	UPDATE io SET output = output || CASE SUBSTR(NEW.program_opt, NEW.program_ptr + LENGTH(repeat), 1)
		WHEN '.' THEN (
			SELECT REPLACE(PRINTF('%.*c', CAST(repeat AS BIGINT), '.'), '.', (
				SELECT CHAR(cell) FROM tape WHERE rowid = caret
			))
		)
		ELSE ''
	END;

	UPDATE inter SET program_ptr = CASE SUBSTR(NEW.program_opt, NEW.program_ptr, 1)
		WHEN '[' THEN
			CASE (SELECT cell FROM tape WHERE rowid = (SELECT caret FROM io))
				WHEN 0 THEN (SELECT right + 1 FROM loops WHERE left = NEW.program_ptr)
				ELSE NEW.program_ptr + 1
			END
		WHEN ']' THEN
			CASE (SELECT cell FROM tape WHERE rowid = (SELECT caret FROM io))
				WHEN 0 THEN NEW.program_ptr + 1 
				ELSE (SELECT left + 1 FROM loops WHERE right = NEW.program_ptr)
			END
		ELSE NEW.program_ptr + (SELECT LENGTH(repeat) + 1 FROM io)
	END;
END;
