--> Drop target table index (if exists)
DROP INDEX IF EXISTS {target_schema}.{index_name};

--> Truncate target table
TRUNCATE TABLE {target_table};

--> Remove reference time column
ALTER TABLE {target_table} DROP COLUMN IF EXISTS reference_time;
ALTER TABLE {target_table} RENAME TO {target_table_only}_stage;
SELECT * INTO {target_table} FROM {target_table}_stage;
DROP TABLE {target_table}_stage;