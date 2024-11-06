-- This creates the four tables on a RDS db needed for a cached fim pipeline run.
CREATE TABLE IF NOT EXISTS {db_fim_table}_flows
(
    hand_id integer,
    hydro_id integer,
    feature_id bigint,
    huc8 integer,
    branch bigint,
    reference_time text,
    discharge_cms double precision,
    discharge_cfs double precision,
    prc_status text
);

CREATE TABLE IF NOT EXISTS {db_fim_table} 
(
    hand_id integer,
    forecast_discharge_cfs double precision,
	forecast_stage_ft double precision,
    rc_discharge_cfs double precision,
    rc_previous_discharge_cfs double precision,
    rc_stage_ft integer,
    rc_previous_stage_ft integer,
    max_rc_stage_ft double precision,
    max_rc_discharge_cfs double precision,
    fim_version varchar(12) DEFAULT '{fim_version}',
    model_version varchar(20),
    reference_time varchar(30),
	prc_method text
);

CREATE TABLE IF NOT EXISTS {db_fim_table}_geo (
    hand_id integer,
    rc_stage_ft integer,
    geom geometry(geometry, 3857)
);

CREATE TABLE IF NOT EXISTS {db_fim_table}_zero_stage (
    hand_id integer,
    rc_discharge_cms double precision,
	note text
);

-- Truncate the tables so they are ready for the FIM Config run
TRUNCATE {db_fim_table}_flows;
TRUNCATE {db_fim_table};
TRUNCATE {db_fim_table}_geo;
TRUNCATE {db_fim_table}_zero_stage;