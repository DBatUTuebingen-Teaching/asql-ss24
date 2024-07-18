#! /bin/bash
# SQL-based animation of Conway's Game of Life
#
# Usage: ./conway.sh ‹number of generations to display›

clear
for N in `jot $1 1 $1`
do
  echo -ne '\033[0;0H'
  echo Generation \#$N
  duckdb -cmd "CREATE MACRO N() AS $N;" -list -noheader < game-of-life.sql
  sleep 0.2
done
