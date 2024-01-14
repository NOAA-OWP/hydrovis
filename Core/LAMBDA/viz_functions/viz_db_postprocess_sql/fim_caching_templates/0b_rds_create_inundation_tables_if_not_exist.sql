-- This creates the four tables on a RDS db needed for a cached fim pipeline run.
-- These four tables exist on both RDS and Redshift, so any changes here will need to be synced with the Redshift version as well - 0a_redshift_create_inundation_tables_if_not_exist.sql
CREATE TABLE IF NOT EXISTS {db_fim_table}_flows
(
    hand_id integer,
    hydro_id integer,
    feature_id integer,
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
    rc_previous_stage_ft double precision,
    max_rc_stage_ft double precision,
    max_rc_discharge_cfs double precision,
    fim_version text,
    reference_time text,
	prc_method text
);

CREATE TABLE IF NOT EXISTS {db_fim_table}_geo (
    hand_id integer,
    rc_stage_ft integer,
	geom_part integer,
    geom geometry(geometry, 3857)
);

CREATE TABLE IF NOT EXISTS {db_fim_table}_zero_stage (
    hand_id integer,
    rc_discharge_cms double precision,
	note text
);

 -- Create a view that contains subdivided polygons in WKT text, for import into Redshift
 CREATE OR REPLACE VIEW {db_fim_table}_geo_view AS
   SELECT fim_subdivide.hand_id,
      fim_subdivide.rc_stage_ft,
      0 AS geom_part,
      st_astext(fim_subdivide.geom) AS geom_wkt
      FROM ( SELECT fim.hand_id,
               fim.rc_stage_ft,
               st_subdivide(fim_geo.geom) AS geom
            FROM {db_fim_table} fim
            JOIN {db_fim_table}_geo fim_geo ON fim.hand_id = fim_geo.hand_id
            WHERE fim.prc_method = 'HAND_Processing'::text) fim_subdivide;
