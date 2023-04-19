CREATE INDEX {index_name} ON {target_table} {index_columns};

ALTER TABLE {target_table}
ADD COLUMN reference_time TEXT DEFAULT '1900-01-01 00:00:00 UTC';

UPDATE admin.ingest_status
SET status = 'Import Complete',
    update_time = now()::timestamp without time zone,
    files_processed = {files_imported},
    records_imported = {rows_imported}
WHERE target = '{target_table}' AND reference_time = '1900-01-01 00:00:00';