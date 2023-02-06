--> Drop table if exists, just in case it's already there.
DROP TABLE IF EXISTS {target_table};

--> Create new table from original
CREATE TABLE {target_table} (LIKE {original_table});