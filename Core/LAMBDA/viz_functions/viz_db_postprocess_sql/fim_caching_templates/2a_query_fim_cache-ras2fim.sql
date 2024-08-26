-- This SQL queries the ras2fim cache on RDS, and inserts appropriate rows into the fim tables of the given run.
INSERT INTO {db_fim_table}(
    hand_id, forecast_discharge_cfs,
    rc_discharge_cfs, rc_previous_discharge_cfs, rc_stage_ft, rc_previous_stage_ft,
    max_rc_stage_ft, max_rc_discharge_cfs, fim_version, reference_time, prc_method
)

SELECT
    fs.hand_id,
    fs.discharge_cfs as forecast_discharge_cfs,
	gc.discharge_cfs as rc_discharge_cfs,
	gc.previous_discharge_cfs as rc_previous_discharge_cfs,
    gc.stage_ft as rc_stage_ft,
	gc.previous_stage_ft as rc_previous_stage_ft,
    mgc.max_rc_stage_ft,
    mgc.max_rc_discharge_cfs,
    gc.fim_version,
    '{reference_time}' as reference_time,
    'Ras2FIM' AS prc_method
FROM ras2fim.geocurves gc
JOIN {db_fim_table}_flows fs ON fs.feature_id = gc.feature_id
JOIN ras2fim.max_geocurves mgc ON gc.feature_id = mgc.feature_id
JOIN {db_fim_table} fim ON fs.hand_id = fim.hand_id
WHERE gc.discharge_cfs >= fs.discharge_cfs AND gc.previous_discharge_cfs < fs.discharge_cfs;

INSERT INTO {db_fim_table}_geo (hand_id, rc_stage_ft, geom)
SELECT fim.hand_id, fim.rc_stage_ft, ST_Transform(gc.geom, 3857) as geom
FROM {db_fim_table} AS fim
JOIN {db_fim_table}_flows fs ON fim.hand_id = fs.hand_id
JOIN ras2fim.geocurves AS gc ON fs.feature_id = gc.feature_id AND fim.rc_stage_ft = gc.stage_ft;

-- Update the flows table prc_status column to reflect the features that were inserted from Ras2FIM cache.
UPDATE {db_fim_table}_flows AS flows
SET prc_status = 'Inserted FROM Ras2FIM Cache'
FROM {db_fim_table} AS fim
WHERE flows.hand_id = fim.hand_id
	  AND fim.prc_method = 'Ras2FIM'