CREATE TABLE IF NOT EXISTS {rs_fim_table}_flows
(
    feature_id integer,
    hydro_id integer,
    huc8 INTEGER,
    branch bigint,
    reference_time text,
    discharge_cms double precision,
    discharge_cfs double precision,
    prc_status text,
    PRIMARY KEY("hydro_id", "feature_id", "huc8", "branch")
);

CREATE TABLE IF NOT EXISTS {rs_fim_table} (
    hydro_id integer,
    feature_id integer,
    huc8 integer,
    branch bigint,
    forecast_discharge_cfs double precision,
    forecast_stage_ft double precision,
    rc_discharge_cfs double precision,
    rc_previous_discharge_cfs double precision,
    rc_stage_ft double precision,
    rc_previous_stage_ft double precision,
    max_rc_discharge_cfs double precision,
    max_rc_stage_ft double precision,
    fim_version text,
    reference_time text,
    prc_method text,
    PRIMARY KEY("hydro_id", "feature_id", "huc8", "branch")
) DISTSTYLE AUTO;

CREATE TABLE IF NOT EXISTS {rs_fim_table}_geo (
    hydro_id integer,
    feature_id integer,
    huc8 INTEGER,
    branch bigint,
    rc_stage_ft integer,
    geom_part integer,
    geom geometry
) DISTSTYLE AUTO;

CREATE TABLE IF NOT EXISTS {rs_fim_table}_zero_stage
(
    feature_id integer,
    hydro_id integer,
    huc8 INTEGER,
    branch bigint,
    rc_discharge_cms double precision,
    note text,
    PRIMARY KEY("hydro_id", "feature_id", "huc8", "branch")
);
