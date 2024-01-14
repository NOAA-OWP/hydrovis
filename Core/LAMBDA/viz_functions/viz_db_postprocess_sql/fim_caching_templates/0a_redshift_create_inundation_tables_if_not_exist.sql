-- First, let's ensure the Redshift cache tables exist
CREATE TABLE IF NOT EXISTS fim.hydrotable_cached_max(
    hand_id INTEGER,
    fim_version TEXT,
    max_rc_discharge_cfs DOUBLE PRECISION,
    max_rc_stage_ft INTEGER,
    PRIMARY KEY(hand_id)
)
DISTKEY(hand_id)
SORTKEY(hand_id);

CREATE TABLE IF NOT EXISTS fim.hydrotable_cached(
    hand_id INTEGER,
    rc_discharge_cfs DOUBLE PRECISION,
    rc_previous_discharge_cfs DOUBLE PRECISION,
    rc_stage_ft INTEGER,
    rc_previous_stage_ft DOUBLE PRECISION,
    PRIMARY KEY(hand_id, rc_stage_ft),
    FOREIGN KEY(hand_id) references fim.hydrotable_cached_max(hand_id)
)
DISTKEY(hand_id)
COMPOUND SORTKEY(hand_id, rc_stage_ft);

CREATE TABLE IF NOT EXISTS fim.hydrotable_cached_geo(
    hand_id INTEGER,
    rc_stage_ft INTEGER,
    geom_part INTEGER,
    geom GEOMETRY,
    FOREIGN KEY(hand_id, rc_stage_ft) references fim.hydrotable_cached(hand_id, rc_stage_ft),
    FOREIGN KEY(hand_id) references fim.hydrotable_cached_max(hand_id)
)
DISTKEY(hand_id)
COMPOUND SORTKEY(hand_id, rc_stage_ft);

CREATE TABLE IF NOT EXISTS fim.hydrotable_cached_zero_stage(
    hand_id INTEGER,
    rc_discharge_cms DOUBLE PRECISION,
    note TEXT,
    PRIMARY KEY(hand_id, rc_discharge_cms),
    FOREIGN KEY(hand_id) references fim.hydrotable_cached_max(hand_id)
)
DISTKEY(hand_id)
SORTKEY(hand_id);

-- This creates the four tables on a Redshift db needed for a cached fim pipeline run.
-- These four tables exist on both RDS and Redshift, so any changes here will need to be synced with the RDS version as well - 0b_rds_create_inundation_tables_if_not_exist.sql
CREATE TABLE IF NOT EXISTS {rs_fim_table}_flows
(
    hand_id INTEGER,
    feature_id integer,
    hydro_id integer,
    huc8 INTEGER,
    branch bigint,
    reference_time text,
    discharge_cms double precision,
    discharge_cfs double precision,
    prc_status text,
    PRIMARY KEY(hand_id)
)
DISTKEY(hand_id)
COMPOUND SORTKEY(hand_id, feature_id);

CREATE TABLE IF NOT EXISTS {rs_fim_table} (
    hand_id integer,
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
    PRIMARY KEY(hand_id, rc_stage_ft),
    FOREIGN KEY(hand_id) references {rs_fim_table}_flows(hand_id),
    FOREIGN KEY(hand_id, rc_stage_ft) references fim.hydrotable_cached(hand_id, rc_stage_ft)
)
DISTKEY(hand_id)
COMPOUND SORTKEY(hand_id, rc_stage_ft);

CREATE TABLE IF NOT EXISTS {rs_fim_table}_geo (
    hand_id integer,
    rc_stage_ft integer,
    geom_part integer,
    geom geometry,
    FOREIGN KEY(hand_id) references {rs_fim_table}_flows(hand_id),
    FOREIGN KEY(hand_id, rc_stage_ft) references {rs_fim_table}(hand_id, rc_stage_ft)
)
DISTKEY(hand_id)
COMPOUND SORTKEY(hand_id, rc_stage_ft);

CREATE TABLE IF NOT EXISTS {rs_fim_table}_zero_stage
(
    hand_id integer,
    rc_discharge_cms double precision,
    note text,
    PRIMARY KEY(hand_id, rc_discharge_cms),
    FOREIGN KEY(hand_id) references {rs_fim_table}_flows(hand_id),
    FOREIGN KEY(hand_id, rc_discharge_cms) references fim.hydrotable_cached_zero_stage(hand_id, rc_discharge_cms)
)
DISTKEY(hand_id)
SORTKEY(hand_id);
