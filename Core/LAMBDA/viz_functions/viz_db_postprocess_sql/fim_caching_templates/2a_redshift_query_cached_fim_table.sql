-- This is the query that pulls cached hand fim from the cache on Redshift. It does this by joining to the just-populated flows table, with WHERE clauses on discharge
-- As of right now, feature_id, hydro_id, huc8, branch, and stage combine to represent a primary key in the hand hydrotables, so all of those fields are used in joins
-- (I've asked the fim team to hash a single unique id for feature_id, hydro_id, huc8, branch combinations... which will simplify these queries, and hopefully help with performance.
TRUNCATE {rs_fim_table};
TRUNCATE {rs_fim_table}_geo;
TRUNCATE {rs_fim_table}_zero_stage;
INSERT INTO {rs_fim_table}(hand_id, forecast_discharge_cfs, rc_discharge_cfs, rc_previous_discharge_cfs, rc_stage_ft, rc_previous_stage_ft,
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
FROM {rs_fim_table}_flows AS fs
JOIN fim.hydrotable_cached_max AS cfm ON fs.hand_id = cfm.hand_id
JOIN fim.hydrotable_cached AS cf ON fs.hand_id = cf.hand_id
WHERE (fs.discharge_cfs <= cf.rc_discharge_cfs AND fs.discharge_cfs > cf.rc_previous_discharge_cfs) OR (fs.discharge_cfs >= cfm.max_rc_discharge_cfs);

INSERT INTO {rs_fim_table}_geo(hand_id, rc_stage_ft, geom_part, geom)
SELECT fim.hand_id, fim.rc_stage_ft, row_number() OVER ()::integer AS geom_part, geom
FROM {rs_fim_table} AS fim
JOIN fim.hydrotable_cached_geo AS cfg ON fim.hand_id = cfg.hand_id AND fim.rc_stage_ft = cfg.rc_stage_ft;

INSERT INTO {rs_fim_table}_zero_stage(hand_id, rc_discharge_cms, note)
SELECT zero_stage.hand_id, zero_stage.rc_discharge_cms, zero_stage.note
FROM fim.hydrotable_cached_zero_stage AS zero_stage
JOIN {rs_fim_table}_flows AS flows
ON flows.hand_id = zero_stage.hand_id
WHERE (flows.discharge_cms <= zero_stage.rc_discharge_cms) OR zero_stage.rc_discharge_cms = 0;

UPDATE {rs_fim_table}_flows AS flows
SET prc_status = 'Cached'
FROM {rs_fim_table} AS fim
WHERE flows.hand_id = fim.hand_id;

UPDATE {rs_fim_table}_flows AS flows
SET prc_status = 'Zero_Stage'
FROM {rs_fim_table}_zero_stage AS zero_stage
WHERE flows.hand_id = zero_stage.hand_id;