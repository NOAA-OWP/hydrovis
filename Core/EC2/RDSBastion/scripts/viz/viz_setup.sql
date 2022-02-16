-- ROLES

CREATE ROLE viz_proc_admin_rw_user;
ALTER ROLE viz_proc_admin_rw_user WITH INHERIT NOCREATEROLE NOCREATEDB LOGIN NOBYPASSRLS CONNECTION LIMIT 500 ENCRYPTED PASSWORD '${VIZ_PROC_ADMIN_RW_PASS}';

-- Wipe the database to make sure this is a clean load
DROP SCHEMA IF EXISTS admin CASCADE;
DROP SCHEMA IF EXISTS ingest CASCADE;
DROP SCHEMA IF EXISTS derived CASCADE;
DROP SCHEMA IF EXISTS fim CASCADE;
DROP SCHEMA IF EXISTS cache CASCADE;
DROP SCHEMA IF EXISTS publish CASCADE;

-- Maybe we should run a vacuum here?

-- Create the schemas
CREATE SCHEMA admin;
CREATE SCHEMA ingest;
CREATE SCHEMA derived;
CREATE SCHEMA fim;
CREATE SCHEMA cache;
CREATE SCHEMA publish;

-- Create the ingest status table
CREATE TABLE admin.ingest_status (
        target character varying(100) NOT NULL,
        reference_time timestamp without time zone,
        status character varying(25),
        update_time timestamp without time zone,
        files_processed integer,
        records_imported bigint,
        insert_time_minutes double precision
);
ALTER TABLE admin.ingest_status OWNER TO viz_proc_admin_rw_user;

-- Create the publish status table
CREATE TABLE admin.publish_status (
        service character varying(100) NOT NULL,
        reference_time timestamp without time zone,
        pp_complete_time timestamp without time zone,
        publish_action character varying(100)
);
ALTER TABLE admin.publish_status OWNER TO viz_proc_admin_rw_user;

-- Create the service table
CREATE TABLE IF NOT EXISTS admin.services
(
    service text,
    folder text,
    configuration text,
    data_sources text,
    ingest_table text,
    postprocess_parents text,
    name text,
    summary text,
    description text,
    tags text,
    credits text,
    run boolean,
    feature_service boolean
);
ALTER TABLE admin.services OWNER TO viz_proc_admin_rw_user;

\copy admin.services from ${HOME}/services.csv delimiter ',' csv header;

-- Create the nwm data tables
    
-------- CONUS tables --------
CREATE TABLE ingest.nwm_channel_rt_ana (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);
ALTER TABLE ingest.nwm_channel_rt_ana OWNER TO viz_proc_admin_rw_user;

CREATE TABLE ingest.nwm_channel_rt_mrf_mem1 (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);
ALTER TABLE ingest.nwm_channel_rt_mrf_mem1 OWNER TO viz_proc_admin_rw_user;

CREATE TABLE ingest.nwm_channel_rt_srf (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);
ALTER TABLE ingest.nwm_channel_rt_srf OWNER TO viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_ana
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    valid_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_ana OWNER to viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_ana_14day
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    reference_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_ana_14day OWNER to viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_srf
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    reference_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_srf OWNER to viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_mrf_3day
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    reference_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_mrf_3day OWNER to viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_mrf_5day
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    reference_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_mrf_5day OWNER to viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_mrf_10day
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    reference_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_mrf_10day OWNER to viz_proc_admin_rw_user;

CREATE TABLE fim.fr_catchments_conus
(
    hydro_id integer,
    geom geometry,
    coastal boolean
);

CREATE TABLE fim.ms_catchments_conus
(
    hydro_id integer,
    geom geometry,
    coastal boolean
);

-------- HI tables --------

CREATE TABLE ingest.nwm_channel_rt_ana_hi (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);
ALTER TABLE ingest.nwm_channel_rt_ana_hi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE ingest.nwm_channel_rt_srf_hi (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);
ALTER TABLE ingest.nwm_channel_rt_srf_hi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_ana_hi
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    valid_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_ana_hi OWNER to viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_srf_hi
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    valid_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_srf_hi OWNER to viz_proc_admin_rw_user;

CREATE TABLE fim.fr_catchments_hi
(
    hydro_id integer,
    geom geometry
)
\copy fim.fr_catchments_hi from ${HOME}/fim_catchments_${FIM_VERSION}_fr_hi.csv delimiter ',' csv header;
SELECT UpdateGeometrySRID('fim', 'fr_catchments_hi', 'geom', 3857);
CREATE INDEX fr_catchments_hi_geom_idx ON fim.fr_catchments_hi USING GIST (geom);
CREATE INDEX fr_catchments_hi_idx ON fim.fr_catchments_hi USING btree (hydro_id);
ALTER TABLE derived.channels_prvi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE fim.ms_catchments_hi
(
    hydro_id integer,
    geom geometry
);
\copy fim.ms_catchments_hi from ${HOME}/fim_catchments_${FIM_VERSION}_ms_hi.csv delimiter ',' csv header;
SELECT UpdateGeometrySRID('fim', 'ms_catchments_hi', 'geom', 3857);
CREATE INDEX ms_catchments_hi_geom_idx ON fim.ms_catchments_hi USING GIST (geom);
CREATE INDEX ms_catchments_hi_idx ON fim.ms_catchments_hi USING btree (hydro_id);
ALTER TABLE derived.channels_prvi OWNER TO viz_proc_admin_rw_user;

-------- PRVI tables --------
CREATE TABLE ingest.nwm_channel_rt_ana_prvi (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);
ALTER TABLE ingest.nwm_channel_rt_ana_prvi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE ingest.nwm_channel_rt_srf_prvi (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);
ALTER TABLE ingest.nwm_channel_rt_srf_prvi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_ana_prvi
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    valid_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_ana_prvi OWNER to viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_srf_prvi
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    valid_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_srf_prvi OWNER to viz_proc_admin_rw_user;

CREATE TABLE fim.fr_catchments_prvi
(
    hydro_id integer,
    geom geometry
)
\copy fim.fr_catchments_prvi from ${HOME}/fim_catchments_${FIM_VERSION}_fr_prvi.csv delimiter ',' csv header;
SELECT UpdateGeometrySRID('fim', 'fr_catchments_prvi', 'geom', 3857);
CREATE INDEX fr_catchments_prvi_geom_idx ON fim.fr_catchments_prvi USING GIST (geom);
CREATE INDEX fr_catchments_prvi_idx ON fim.fr_catchments_prvi USING btree (hydro_id);
ALTER TABLE derived.channels_prvi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE fim.ms_catchments_prvi
(
    hydro_id integer,
    geom geometry
);
\copy fim.ms_catchments_prvi from ${HOME}/fim_catchments_${FIM_VERSION}_ms_prvi.csv delimiter ',' csv header;
SELECT UpdateGeometrySRID('fim', 'ms_catchments_prvi', 'geom', 3857);
CREATE INDEX ms_catchments_prvi_geom_idx ON fim.ms_catchments_prvi USING GIST (geom);
CREATE INDEX ms_catchments_prvi_idx ON fim.ms_catchments_prvi USING btree (hydro_id);
ALTER TABLE derived.channels_prvi OWNER TO viz_proc_admin_rw_user;

-- Create the recurrence flows tables
CREATE TABLE derived.recurrence_flows_conus (
    feature_id integer,
    rf_1_3 double precision,
    rf_1_4 double precision,
    rf_1_5 double precision,
    rf_1_6 double precision,
    rf_1_7 double precision,
    rf_1_8 double precision,
    rf_1_9 double precision,
    rf_2_0 double precision,
    rf_2_1 double precision,
    rf_2_2 double precision,
    rf_2_3 double precision,
    rf_2_4 double precision,
    rf_2_5 double precision,
    rf_2_6 double precision,
    rf_2_7 double precision,
    rf_2_8 double precision,
    rf_2_9 double precision,
    rf_3_0 double precision,
    rf_3_5 double precision,
    rf_4_0 double precision,
    rf_5_0 double precision,
    rf_10_0 double precision,
    rf_2_0_17c double precision,
    rf_5_0_17c double precision,
    rf_10_0_17c double precision,
    rf_25_0_17c double precision,
    rf_50_0_17c double precision,
    rf_100_0_17c double precision
);

\copy derived.recurrence_flows_conus from ${HOME}/nwm_v21_recurrence_flows.csv delimiter ',' csv header;
ALTER TABLE derived.recurrence_flows_conus ADD COLUMN bankfull DOUBLE PRECISION;
CREATE INDEX recurrence_flows_conus_idx ON derived.recurrence_flows_conus USING btree (feature_id);
ALTER TABLE derived.recurrence_flows_conus OWNER TO viz_proc_admin_rw_user;

CREATE TABLE derived.huc2_rf_thresholds (
    huc2 integer,
    region_name text,
    recurrence_flow text,
    recurrence_flow_method text,
    nwm_data_source double precision
);

\copy derived.huc2_rf_thresholds from ${HOME}/huc2_rf_thresholds.csv delimiter ',' csv header;
ALTER TABLE derived.huc2_rf_thresholds OWNER TO viz_proc_admin_rw_user;

CREATE TABLE derived.featureid_huc_crosswalk(
    feature_id integer NOT NULL,
    huc12 bigint,
    huc10 bigint,
    huc8 integer,
    huc6 integer,
    huc4 integer,
    huc2 integer
);

\copy derived.featureid_huc_crosswalk from ${HOME}/featureid_huc_crosswalk.csv delimiter ',' csv header;
CREATE INDEX featureid_huc_crosswalk_idx ON derived.featureid_huc_crosswalk USING btree (feature_id);
ALTER TABLE derived.featureid_huc_crosswalk OWNER TO viz_proc_admin_rw_user;

UPDATE derived.recurrence_flows_conus AS rf_conus
SET bankfull = CASE
                                        WHEN hrft.recurrence_flow= 'rf_1_3' THEN rf_1_3
                                        WHEN hrft.recurrence_flow= 'rf_1_4' THEN rf_1_4
                                        WHEN hrft.recurrence_flow= 'rf_1_5' THEN rf_1_5
                                        WHEN hrft.recurrence_flow= 'rf_1_6' THEN rf_1_6
                                        WHEN hrft.recurrence_flow= 'rf_1_7' THEN rf_1_7
                                        WHEN hrft.recurrence_flow= 'rf_1_8' THEN rf_1_8
                                        WHEN hrft.recurrence_flow= 'rf_1_9' THEN rf_1_9
                                        WHEN hrft.recurrence_flow= 'rf_2_0' THEN rf_2_0
                                        WHEN hrft.recurrence_flow= 'rf_2_1' THEN rf_2_1
                                        WHEN hrft.recurrence_flow= 'rf_2_2' THEN rf_2_2
                                        WHEN hrft.recurrence_flow= 'rf_2_3' THEN rf_2_3
                                        WHEN hrft.recurrence_flow= 'rf_2_4' THEN rf_2_4
                                        WHEN hrft.recurrence_flow= 'rf_2_5' THEN rf_2_5
                                        WHEN hrft.recurrence_flow= 'rf_2_6' THEN rf_2_6
                                        WHEN hrft.recurrence_flow= 'rf_2_7' THEN rf_2_7
                                        WHEN hrft.recurrence_flow= 'rf_2_8' THEN rf_2_8
                                        WHEN hrft.recurrence_flow= 'rf_2_9' THEN rf_2_9
                                        WHEN hrft.recurrence_flow= 'rf_3_0' THEN rf_3_0
                                        WHEN hrft.recurrence_flow= 'rf_3_5' THEN rf_3_5
                                        WHEN hrft.recurrence_flow= 'rf_4_0' THEN rf_4_0
                                        WHEN hrft.recurrence_flow= 'rf_5_0' THEN rf_5_0
                                        WHEN hrft.recurrence_flow= 'rf_10_0' THEN rf_10_0
                                        WHEN hrft.recurrence_flow= 'rf_2_0_17c' THEN rf_2_0_17c
                                        WHEN hrft.recurrence_flow= 'rf_5_0_17c' THEN rf_5_0_17c
                                        WHEN hrft.recurrence_flow= 'rf_10_0_17c' THEN rf_10_0_17c
                                        WHEN hrft.recurrence_flow= 'rf_25_0_17c' THEN rf_25_0_17c
                                        WHEN hrft.recurrence_flow= 'rf_50_0_17c' THEN rf_50_0_17c
                                        WHEN hrft.recurrence_flow= 'rf_100_0_17c' THEN rf_100_0_17c
                                        ELSE NULL
                           END
FROM derived.featureid_huc_crosswalk AS fhc, derived.huc2_rf_thresholds AS hrft
WHERE fhc.feature_id = rf_conus.feature_id AND fhc.huc2 = hrft.huc2;

CREATE TABLE derived.recurrence_flows_hi (
    feature_id integer,
    rf_2_0 double precision,
    rf_5_0 double precision,
    rf_10_0 double precision,
    rf_25_0 double precision,
    rf_50_0 double precision,
    rf_100_0 double precision,
    rf_500_0 double precision,
    huc6 text
);

\copy derived.recurrence_flows_hi from ${HOME}/nwm_v20_recurrence_flows_hawaii.csv delimiter ',' csv header;
ALTER TABLE derived.recurrence_flows_hi ADD COLUMN bankfull DOUBLE PRECISION; 
UPDATE derived.recurrence_flows_hi SET bankfull = ${RECURR_FLOW_HI};
CREATE INDEX recurrence_flows_hi_idx ON derived.recurrence_flows_hi USING btree (feature_id);
ALTER TABLE derived.recurrence_flows_hi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE derived.recurrence_flows_prvi (
    feature_id integer,
    rf_2_0 double precision,
    rf_5_0 double precision,
    rf_10_0 double precision,
    rf_25_0 double precision,
    rf_50_0 double precision,
    rf_100_0 double precision,
    rf_500_0 double precision,
    huc6 text
);

\copy derived.recurrence_flows_prvi from ${HOME}/nwm_v21_recurrence_flows_prvi.csv delimiter ',' csv header;
ALTER TABLE derived.recurrence_flows_prvi ADD COLUMN bankfull DOUBLE PRECISION; 
UPDATE derived.recurrence_flows_prvi SET bankfull = ${RECURR_FLOW_PRVI};
CREATE INDEX recurrence_flows_prvi_idx ON derived.recurrence_flows_prvi USING btree (feature_id);
ALTER TABLE derived.recurrence_flows_prvi OWNER TO viz_proc_admin_rw_user;

-- Create the channels tables
CREATE TABLE derived.channels_conus
(
    feature_id integer,
    strm_order bigint,
    name character varying(100),
    huc6 text,
    nwm_vers double precision,
    geom geometry
);

\copy derived.channels_conus from ${HOME}/nwm_v21_web_mercator_channels.csv delimiter ',' csv header;
SELECT UpdateGeometrySRID('derived', 'channels_conus', 'geom', 3857);
CREATE INDEX channels_conus_geom_idx ON derived.channels_conus USING GIST (geom);
CREATE INDEX channels_conus_idx ON derived.channels_conus USING btree (feature_id);
ALTER TABLE derived.channels_conus OWNER TO viz_proc_admin_rw_user;

CREATE TABLE derived.channels_hi
(
    feature_id integer,
    strm_order bigint,
    name character varying(100),
    huc6 text,
    nwm_vers double precision,
    geom geometry
);

\copy derived.channels_hi from ${HOME}/nwm_v21_web_mercator_channels_hi.csv delimiter ',' csv header;
SELECT UpdateGeometrySRID('derived', 'channels_hi', 'geom', 3857);
CREATE INDEX channels_hi_geom_idx ON derived.channels_hi USING GIST (geom);
CREATE INDEX channels_hi_idx ON derived.channels_hi USING btree (feature_id);
ALTER TABLE derived.channels_hi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE derived.channels_prvi
(
    feature_id integer,
    strm_order bigint,
    name character varying(100),
    huc6 text,
    nwm_vers double precision,
    geom geometry
);

\copy derived.channels_prvi from ${HOME}/nwm_v21_web_mercator_channels_prvi.csv delimiter ',' csv header;
SELECT UpdateGeometrySRID('derived', 'channels_prvi', 'geom', 3857);
CREATE INDEX channels_prvi_geom_idx ON derived.channels_prvi USING GIST (geom);
CREATE INDEX channels_prvi_idx ON derived.channels_prvi USING btree (feature_id);
ALTER TABLE derived.channels_prvi OWNER TO viz_proc_admin_rw_user;

-- Create the max flows tables.
CREATE TABLE cache.max_flows_ana (
    feature_id integer,
    maxflow_1hour double precision
);
ALTER TABLE cache.max_flows_ana OWNER TO viz_proc_admin_rw_user;
    
CREATE TABLE cache.max_flows_ana_hi (
    feature_id integer,
    maxflow_1hour double precision
);
ALTER TABLE cache.max_flows_ana_hi OWNER TO viz_proc_admin_rw_user;
    
CREATE TABLE cache.max_flows_ana_prvi (
    feature_id integer,
    maxflow_1hour double precision
);
ALTER TABLE cache.max_flows_ana_prvi OWNER TO viz_proc_admin_rw_user;
    
CREATE TABLE cache.max_flows_mrf (
    feature_id integer,
    maxflow_3day double precision,
    maxflow_5day double precision,
    maxflow_10day double precision
);
ALTER TABLE cache.max_flows_mrf OWNER TO viz_proc_admin_rw_user;

CREATE TABLE cache.max_flows_srf (
    feature_id integer,
    maxflow_18hour double precision
);
ALTER TABLE cache.max_flows_srf OWNER TO viz_proc_admin_rw_user;

CREATE TABLE cache.max_flows_srf_hi (
    feature_id integer,
    maxflow_48hour double precision
);
ALTER TABLE cache.max_flows_srf_hi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE cache.max_flows_srf_prvi(
    feature_id integer,
    maxflow_48hour double precision
);
ALTER TABLE cache.max_flows_srf_prvi OWNER TO viz_proc_admin_rw_user;

-------- RFC tables --------
CREATE TABLE ingest.rnr_max_flows (
    feature_id integer,
    nws_lid text,
    streamflow double precision,
    forecast_available_value integer,
    has_ahps_forecast boolean,
    forecast_feature_id integer,
    forecast_nws_lid text,
    forecast_issue_time timestamp,
    forecast_max_value double precision,
    forecast_max_valid_time timestamp,
    forecast_max_status text,
    forecast_reach_count integer,
    viz_status_lid text,
    viz_max_status text,
    viz_status_reason text,
    waterbody_status text,
    waterbody_id text
);
ALTER TABLE ingest.rnr_max_flows OWNER TO viz_proc_admin_rw_user;

CREATE TABLE ingest.fim_catchments_rnr
(
    hydro_id integer,
    streamflow double precision,
    interpolated_stage double precision,
    feature_id integer,
    fim_version text,
    valid_time timestamp without time zone,
    fim_configuration text,
    max_rc_h double precision,
    max_rc_q double precision
)
ALTER TABLE ingest.fim_catchments_rnr OWNER to viz_proc_admin_rw_user;

-- Grant Schemas to User
GRANT ALL ON SCHEMA admin TO viz_proc_admin_rw_user;
GRANT ALL ON SCHEMA ingest TO viz_proc_admin_rw_user;
GRANT ALL ON SCHEMA derived TO viz_proc_admin_rw_user;
GRANT ALL ON SCHEMA cache TO viz_proc_admin_rw_user;
GRANT ALL ON SCHEMA publish TO viz_proc_admin_rw_user;
GRANT ALL ON ALL TABLES IN SCHEMA admin TO viz_proc_admin_rw_user;
GRANT ALL ON ALL TABLES IN SCHEMA ingest TO viz_proc_admin_rw_user;
GRANT ALL ON ALL TABLES IN SCHEMA derived TO viz_proc_admin_rw_user;
GRANT ALL ON ALL TABLES IN SCHEMA cache TO viz_proc_admin_rw_user;
GRANT ALL ON ALL TABLES IN SCHEMA publish TO viz_proc_admin_rw_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA admin GRANT all ON TABLES TO viz_proc_admin_rw_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA ingest GRANT all ON TABLES TO viz_proc_admin_rw_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA derived GRANT all ON TABLES TO viz_proc_admin_rw_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA cache GRANT all ON TABLES TO viz_proc_admin_rw_user;
ALTER DEFAULT PRIVILEGES IN SCHEMA publish GRANT all ON TABLES TO viz_proc_admin_rw_user;