-- usage: sqlite3 personal_catalog.dat < upcscan_schema.sql
CREATE TABLE 'works' (
 id INTEGER PRIMARY key,
 upc TEXT,
 type TEXT,
 title TEXT,
 bywho TEXT,
 description TEXT,
 UNIQUE (upc, type)
);
