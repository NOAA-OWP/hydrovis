-- ROLES

CREATE ROLE viz_proc_admin_rw_user;
ALTER ROLE viz_proc_admin_rw_user WITH INHERIT NOCREATEROLE NOCREATEDB LOGIN NOBYPASSRLS CONNECTION LIMIT 45 ENCRYPTED PASSWORD '${VIZ_PROC_ADMIN_RW_PASS}';

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
    service text COLLATE pg_catalog."default",
    folder text COLLATE pg_catalog."default",
    configuration text COLLATE pg_catalog."default",
    data_sources text COLLATE pg_catalog."default",
    ingest_table text COLLATE pg_catalog."default",
    postprocess_parents text COLLATE pg_catalog."default",
    name text COLLATE pg_catalog."default",
    summary text COLLATE pg_catalog."default",
    description text COLLATE pg_catalog."default",
    tags text COLLATE pg_catalog."default",
    credits text COLLATE pg_catalog."default",
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

-- Create the recurrence flows tables
CREATE TABLE derived.recurrence_flows_conus (
    feature_id integer NOT NULL,
    rf_1_5 double precision,
    rf_2_0 double precision,
    rf_3_0 double precision,
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
CREATE INDEX idx_rf_featureid ON derived.recurrence_flows_conus (feature_id);
ALTER TABLE derived.recurrence_flows_conus ADD COLUMN bankfull DOUBLE PRECISION; 
UPDATE derived.recurrence_flows_conus SET bankfull = ${RECURR_FLOW_CONUS};
ALTER TABLE derived.recurrence_flows_conus OWNER TO viz_proc_admin_rw_user;

CREATE TABLE derived.recurrence_flows_hi (
    feature_id integer NOT NULL,
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
CREATE INDEX idx_rf_hi_featureid ON derived.recurrence_flows_hi (feature_id);
ALTER TABLE derived.recurrence_flows_hi ADD COLUMN bankfull DOUBLE PRECISION; 
UPDATE derived.recurrence_flows_hi SET bankfull = ${RECURR_FLOW_HI};
ALTER TABLE derived.recurrence_flows_hi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE derived.recurrence_flows_prvi (
    feature_id integer NOT NULL,
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
CREATE INDEX idx_rf_prvi_featureid ON derived.recurrence_flows_prvi USING btree (feature_id);
ALTER TABLE derived.recurrence_flows_prvi ADD COLUMN bankfull DOUBLE PRECISION; 
UPDATE derived.recurrence_flows_prvi SET bankfull = ${RECURR_FLOW_PRVI};
ALTER TABLE derived.recurrence_flows_prvi OWNER TO viz_proc_admin_rw_user;

-- Create the channels tables
CREATE TABLE derived.channels_conus
(
    feature_id integer PRIMARY KEY,
    strm_order bigint,
    name character varying(100),
    huc6 text,
    nwm_vers double precision,
    geom geometry
);

\copy derived.channels_conus from ${HOME}/nwm_v21_web_mercator_channels.csv delimiter ',' csv header;
CREATE INDEX idx_ch_featureid ON derived.channels_conus USING btree (feature_id);
select UpdateGeometrySRID('derived', 'channels_conus', 'geom', 3857);
ALTER TABLE derived.channels_conus OWNER TO viz_proc_admin_rw_user;

CREATE TABLE derived.channels_hi
(
    feature_id integer PRIMARY KEY,
    strm_order bigint,
    name character varying(100),
    huc6 text,
    nwm_vers double precision,
    geom geometry
);

\copy derived.channels_hi from ${HOME}/nwm_v21_web_mercator_channels_hi.csv delimiter ',' csv header;
CREATE INDEX idx_ch_hi_featureid ON derived.channels_hi USING btree (feature_id);
select UpdateGeometrySRID('derived', 'channels_hi', 'geom', 3857);
ALTER TABLE derived.channels_hi OWNER TO viz_proc_admin_rw_user;

CREATE TABLE derived.channels_prvi
(
    feature_id integer PRIMARY KEY,
    strm_order bigint,
    name character varying(100),
    huc6 text,
    nwm_vers double precision,
    geom geometry
);

\copy derived.channels_prvi from ${HOME}/nwm_v21_web_mercator_channels_prvi.csv delimiter ',' csv header;
CREATE INDEX idx_ch_prvi_featureid ON derived.channels_prvi USING btree (feature_id);
select UpdateGeometrySRID('derived', 'channels_prvi', 'geom', 3857);
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

-- Grant Schemas to User

GRANT ALL ON ALL TABLES IN SCHEMA admin TO viz_proc_admin_rw_user;
GRANT ALL ON ALL TABLES IN SCHEMA ingest TO viz_proc_admin_rw_user;
GRANT ALL ON ALL TABLES IN SCHEMA derived TO viz_proc_admin_rw_user;
GRANT ALL ON ALL TABLES IN SCHEMA cache TO viz_proc_admin_rw_user;
GRANT ALL ON ALL TABLES IN SCHEMA publish TO viz_proc_admin_rw_user;