-- Query the hand cache.
INSERT INTO {db_fim_table}(hand_id, forecast_discharge_cfs, rc_discharge_cfs, rc_previous_discharge_cfs, rc_stage_ft, rc_previous_stage_ft,
                           max_rc_stage_ft, max_rc_discharge_cfs, fim_version, reference_time, prc_method)
SELECT
    fs.hand_id,
    fs.discharge_cfs AS forecast_discharge_cfs,
    cf.rc_discharge_cfs,
    cf.rc_previous_discharge_cfs,
    cf.rc_stage_ft,
    cf.rc_previous_stage_ft,
    cfm.max_rc_stage_ft,
    cfm.max_rc_discharge_cfs,
    cfm.fim_version,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    'Cached' AS prc_method
FROM {db_fim_table}_flows AS fs
JOIN fim_cache.hand_hydrotable_cached_max AS cfm ON fs.hand_id = cfm.hand_id
JOIN fim_cache.hand_hydrotable_cached AS cf ON fs.hand_id = cf.hand_id
WHERE fs.prc_status = 'Pending' AND ((fs.discharge_cfs <= cf.rc_discharge_cfs AND fs.discharge_cfs > cf.rc_previous_discharge_cfs)
									  OR ((fs.discharge_cfs >= cfm.max_rc_discharge_cfs) AND rc_stage_ft = 83));

INSERT INTO {db_fim_table}_geo(hand_id, rc_stage_ft, geom)
SELECT fim.hand_id, fim.rc_stage_ft, geom
FROM {db_fim_table} AS fim
JOIN fim_cache.hand_hydrotable_cached_geo AS cfg ON fim.hand_id = cfg.hand_id AND fim.rc_stage_ft = cfg.rc_stage_ft
WHERE fim.prc_method = 'Cached';

-- Update the flows table prc_status column to reflect the features that were inserted from cache.
UPDATE {db_fim_table}_flows AS flows
SET prc_status = 'Inserted From HAND Cache'
FROM {db_fim_table} AS fim
WHERE flows.hand_id = fim.hand_id
	  AND fim.prc_method = 'Cached';

-- Update the flows table prc_status column to reflect the features that were inserted from cache.
UPDATE {db_fim_table}_flows AS flows
SET prc_status = 'HAND Cache - Zero Stage'
FROM fim_cache.hand_hydrotable_cached_zero_stage AS zero_stage
WHERE flows.hand_id = zero_stage.hand_id AND flows.prc_status = 'Pending' AND ((flows.discharge_cms <= zero_stage.rc_discharge_cms) OR zero_stage.rc_discharge_cms = 0);