all:
	@echo make initialize.db to initialize catalog

initialize.tp:
	sqlite3 personal_catalog_tp.dat < upcscan_schema.sql

initialize.er:
	sqlite3 personal_catalog_er.dat < upcscan_schema.sql
