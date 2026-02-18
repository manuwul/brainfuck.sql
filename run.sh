#!/usr/bin/env bash

DB_NAME="brainfuck.db"
BF=$(<"$1")
QUERY=$(<"brainfuck.sql")
QUERY+="
.headers on
.mode column
UPDATE inter SET program = '$BF';
SELECT * FROM io;
SELECT * FROM loops;
SELECT * FROM inter;
SELECT * FROM tape LIMIT 10;
"

sqlite3 "$DB_NAME" <<< "$QUERY"
