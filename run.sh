#!/usr/bin/env bash

DB_NAME="brainfuck.db"
BF=$(<"$1")
QUERY="
UPDATE state SET program = '
$BF
';
SELECT output FROM interpreter;"

sqlite3 "$DB_NAME" <<EOF
.bail on
.read brainfuck.sql
UPDATE state SET program = '$BF';
SELECT output FROM interpreter;
EOF
