-- Add an empty row so that service monitor will pick up a reference and update time in the event of no fim features
-- This is far from ideal
INSERT INTO {db_publish_table}(
	hydro_id, hydro_id_str, geom, branch, feature_id, feature_id_str, streamflow_cfs, fim_stage_ft, max_rc_stage_ft, max_rc_discharge_cfs, fim_version, reference_time, huc8)
	VALUES (-9999, '-9999', NULL, 'NA', -9999, '-9999', -9999, -9999, -9999, -9999, 'NA', to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), '-9999');

-- These needs to be added as well, so that the summary queries don't fail because of the dependent tables being empty -
-- There shouldn't be any harm to the fim_config, since this happens at the end... but far from ideal.
INSERT INTO {db_fim_table}_flows(
	hydro_id, branch, feature_id, huc8, reference_time)
	VALUES (-9999, -9999, -9999, -9999, to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'));
	
INSERT INTO {db_fim_table}(
	hand_id, reference_time)
	VALUES (-9999, to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'));
	
INSERT INTO {db_fim_table}_geo(
	hand_id)
	VALUES (-9999);