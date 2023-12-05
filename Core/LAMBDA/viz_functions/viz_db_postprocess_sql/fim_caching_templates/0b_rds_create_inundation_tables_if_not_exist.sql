CREATE TABLE IF NOT EXISTS {db_fim_table}_flows
(
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
    hydro_id integer,
    feature_id integer,
	huc8 integer,
    branch bigint,
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
    hydro_id integer,
    feature_id integer,
	huc8 integer,
	branch bigint,
    rc_stage_ft integer,
	geom_part integer,
    geom geometry(geometry, 3857)
);

CREATE TABLE IF NOT EXISTS {db_fim_table}_zero_stage (
    hydro_id integer,
    feature_id integer,
	huc8 integer,
	branch bigint,
    rc_discharge_cms double precision,
	note text
);

 -- Create a view that contains subdivided polygons in WKT text, for import into Redshift
 CREATE OR REPLACE VIEW {db_fim_table}_geo_view AS
   SELECT fim_subdivide.hydro_id,
      fim_subdivide.feature_id,
      fim_subdivide.huc8,
      fim_subdivide.branch,
      fim_subdivide.rc_stage_ft,
      0 AS geom_part,
      st_astext(fim_subdivide.geom) AS geom_wkt
      FROM ( SELECT fim.hydro_id,
               fim.feature_id,
               fim.huc8,
               fim.branch,
               fim.rc_stage_ft,
               st_subdivide(fim_geo.geom) AS geom
            FROM {db_fim_table} fim
            JOIN {db_fim_table}_geo fim_geo ON fim.hydro_id = fim_geo.hydro_id AND fim.feature_id = fim_geo.feature_id AND fim.huc8 = fim_geo.huc8 AND fim.branch = fim_geo.branch AND fim.rc_stage_ft = fim_geo.rc_stage_ft
            WHERE fim.prc_method = 'HAND_Processing'::text) fim_subdivide;
