CREATE INDEX IF NOT EXISTS {index_name} ON {target_table} {index_columns};

ALTER TABLE {target_table}
ADD COLUMN reference_time TEXT DEFAULT '1900-01-01 00:00:00 UTC';

-- Checks to see if feature_id is a column in the target table
SELECT EXISTS (SELECT 1 
FROM information_schema.columns
WHERE table_schema = '{target_schema}' AND table_name = '{target_table_only}' AND column_name='feature_id');