TRUNCATE {db_fim_table};
TRUNCATE {db_fim_table}_geo;
TRUNCATE {db_fim_table}_zero_stage;

INSERT INTO {db_fim_table}(
	SELECT * FROM dblink('external_vpp_redshift', $REDSHIFT$
	SELECT hydro_id, feature_id, huc8, branch, forecast_discharge_cfs, forecast_stage_ft, rc_discharge_cfs,
					   rc_previous_discharge_cfs, rc_stage_ft, rc_previous_stage_ft, max_rc_stage_ft, max_rc_discharge_cfs,
					   fim_version, reference_time, prc_method
	FROM {redshift_fim_table}; 
	$REDSHIFT$) AS t1 (hydro_id integer, feature_id integer, huc8 integer, branch bigint, forecast_discharge_cfs double precision, forecast_stage_ft double precision, rc_discharge_cfs double precision,
					   rc_previous_discharge_cfs double precision, rc_stage_ft integer, rc_previous_stage_ft double precision, max_rc_stage_ft double precision, max_rc_discharge_cfs double precision,
					   fim_version text, reference_time text, prc_method text)
);

INSERT INTO {db_fim_table}_geo(
	SELECT * FROM dblink('external_vpp_redshift', $REDSHIFT$
	SELECT hydro_id, feature_id, huc8, branch, rc_stage_ft, geom_part, geom
	FROM {redshift_fim_table}_geo; 
	$REDSHIFT$) AS t1 (hydro_id integer, feature_id integer, huc8 integer, branch bigint, rc_stage_ft integer, geom_part integer, geom geometry)
);

INSERT INTO {db_fim_table}_zero_stage(
	SELECT * FROM dblink('external_vpp_redshift', $REDSHIFT$
	SELECT hydro_id , feature_id, huc8, branch, rc_discharge_cms, note
	FROM {redshift_fim_table}_zero_stage; 
	$REDSHIFT$) AS t1 (hydro_id integer, feature_id integer, huc8 integer, branch bigint, rc_discharge_cms double precision, note text)
);