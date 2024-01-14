-- This SQL queries the just-updated hand cache table on RDS, and inserts appropriate rows into the fim tables of the given run.
INSERT INTO {db_fim_table}(
	SELECT * FROM dblink('external_vpp_redshift', $REDSHIFT$
	SELECT hand_id, forecast_discharge_cfs, forecast_stage_ft, rc_discharge_cfs,
					   rc_previous_discharge_cfs, rc_stage_ft, rc_previous_stage_ft, max_rc_stage_ft, max_rc_discharge_cfs,
					   fim_version, reference_time, prc_method
	FROM {rs_fim_table}; 
	$REDSHIFT$) AS t1 (hand_id integer, forecast_discharge_cfs double precision, forecast_stage_ft double precision, rc_discharge_cfs double precision,
					   rc_previous_discharge_cfs double precision, rc_stage_ft integer, rc_previous_stage_ft double precision, max_rc_stage_ft double precision, max_rc_discharge_cfs double precision,
					   fim_version text, reference_time text, prc_method text)
);

INSERT INTO {db_fim_table}_geo(
	SELECT * FROM dblink('external_vpp_redshift', $REDSHIFT$
	SELECT hand_id, rc_stage_ft, geom_part, geom
	FROM {rs_fim_table}_geo; 
	$REDSHIFT$) AS t1 (hand_id integer, rc_stage_ft integer, geom_part integer, geom geometry)
);

INSERT INTO {db_fim_table}_zero_stage(
	SELECT * FROM dblink('external_vpp_redshift', $REDSHIFT$
	SELECT hand_id, rc_discharge_cms, note
	FROM {rs_fim_table}_zero_stage; 
	$REDSHIFT$) AS t1 (hand_id integer, rc_discharge_cms double precision, note text)
);

-- Update the flows table prc_status column to reflect the features that were inserted from Redshift cache.
UPDATE {db_fim_table}_flows AS flows
SET prc_status = 'Inserted FROM HAND Cache'
FROM {db_fim_table} AS fim
WHERE flows.hand_id = fim.hand_id
	  AND fim.prc_method = 'Cached';

-- Update the flows table prc_status column to reflect the features that were inserted from Redshift cache.
UPDATE {db_fim_table}_flows AS flows
SET prc_status = 'Inserted FROM HAND Cache - Zero Stage'
FROM {db_fim_table}_zero_stage AS fim
WHERE flows.hand_id = fim.hand_id;