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
    hydro_id integer ENCODE az64,
    feature_id integer ENCODE az64,
    huc8 integer ENCODE az64,
    branch bigint ENCODE az64,
    forecast_discharge_cfs double precision ENCODE raw,
    forecast_stage_ft double precision ENCODE raw,
    rc_discharge_cfs double precision ENCODE raw,
    rc_previous_discharge_cfs double precision ENCODE raw,
    rc_stage_ft double precision ENCODE raw,
    rc_previous_stage_ft double precision ENCODE raw,
    max_rc_discharge_cfs double precision ENCODE raw,
    max_rc_stage_ft double precision ENCODE raw,
    fim_version character varying(256) ENCODE lzo,
    reference_time character varying(23) ENCODE lzo,
    prc_method character varying(10) ENCODE lzo,
    PRIMARY KEY("hydro_id", "feature_id", "huc8", "branch")
) DISTSTYLE AUTO;

CREATE TABLE IF NOT EXISTS {rs_fim_table}_geo (
    hydro_id integer ENCODE az64,
    feature_id integer ENCODE az64,
    huc8 INTEGER,
    branch bigint ENCODE az64,
    rc_stage_ft integer ENCODE az64,
    geom_part integer ENCODE az64,
    geom geometry ENCODE raw
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
