-- CONFIG
PRAGMA recursive_triggers = ON;
PRAGMA recursive_limit = 1000000;

-- TAPE
DROP TABLE IF EXISTS tape;
CREATE TABLE tape (
    cell TINYINT DEFAULT 0
);
WITH RECURSIVE count(i) AS (
    SELECT 1
    UNION ALL
    SELECT i + 1 FROM count WHERE i < 30000
)
INSERT INTO tape (cell) SELECT 0 FROM count;

-- INTERPRETER
DROP TABLE IF EXISTS interpreter;
CREATE TABLE interpreter (
    caret INTEGER DEFAULT 1,
    input TEXT DEFAULT '',
    output TEXT DEFAULT ''
);
INSERT INTO interpreter DEFAULT VALUES;

-- STATE
DROP TABLE IF EXISTS state;
CREATE TABLE state (
    program TEXT DEFAULT ''
);
INSERT INTO state DEFAULT VALUES;

-- TRIGGER
CREATE TRIGGER step
AFTER UPDATE ON state
WHEN LENGTH(NEW.program) > 0
BEGIN
    UPDATE interpreter SET caret = CASE SUBSTR(NEW.program, 1, 1)
        WHEN '>' THEN MIN(caret + 1, 30000)
        WHEN '<' THEN MAX(caret - 1, 0)
        ELSE caret
    END;
    
    UPDATE tape SET cell = CASE SUBSTR(NEW.program, 1, 1)
        WHEN '+' THEN (cell + 1) % 256
        WHEN '-' THEN (cell + 255) % 256
		WHEN ',' THEN COALESCE((SELECT UNICODE(input) FROM interpreter), 0)
        ELSE cell
    END
    WHERE rowid = (SELECT caret FROM interpreter);
	UPDATE interpreter SET input = CASE SUBSTR(NEW.program, 1, 1)
		WHEN ',' THEN SUBSTR(input, 2)
		ELSE input
	END;
    
	UPDATE interpreter SET output = CASE SUBSTR(NEW.program, 1, 1)
		WHEN '.' THEN CONCAT(output, (
			SELECT CHAR(cell) FROM tape WHERE rowid = (SELECT caret FROM interpreter)))
		ELSE output
	END;
	
    UPDATE state SET program = SUBSTR(NEW.program, 2);
END;
