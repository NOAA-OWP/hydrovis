CREATE INDEX {index_name} ON {target_table} {index_columns};

ALTER TABLE {target_table}
ADD COLUMN reference_time TEXT DEFAULT '1900-01-01 00:00:00 UTC';