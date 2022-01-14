-- ROLES

CREATE ROLE viz_proc_admin_rw_user;
ALTER ROLE viz_proc_admin_rw_user WITH INHERIT NOCREATEROLE NOCREATEDB LOGIN NOBYPASSRLS CONNECTION LIMIT 45 ENCRYPTED PASSWORD '${VIZ_PROC_ADMIN_RW_PASS}';

-- Create the schemas
CREATE SCHEMA admin;
CREATE SCHEMA ingest;
CREATE SCHEMA derived;
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

-- Create the publish status table
CREATE TABLE admin.publish_status (
        service character varying(100) NOT NULL,
        reference_time timestamp without time zone,
        pp_complete_time timestamp without time zone,
        publish_action character varying(100)
);

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

\copy admin.services from ${HOME}/services.csv delimiter ',' csv header;

-- Create the nwm data tables
    
-------- CONUS tables --------
CREATE TABLE ingest.nwm_channel_rt_ana (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);

CREATE TABLE ingest.nwm_channel_rt_mrf_mem1 (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);

CREATE TABLE ingest.nwm_channel_rt_srf (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);

-------- HI tables --------
CREATE TABLE ingest.nwm_channel_rt_ana_hi (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);

CREATE TABLE ingest.nwm_channel_rt_srf_hi (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);

-------- PRVI tables --------
CREATE TABLE ingest.nwm_channel_rt_ana_prvi (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);

CREATE TABLE ingest.nwm_channel_rt_srf_prvi (
    feature_id integer,
    forecast_hour integer,
    streamflow double precision
);

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

-- Create the FIM channels tables
CREATE TABLE derived.fim_channels_conus
(
    hydro_id integer PRIMARY KEY,
    huc6 text,
    fim_vers double precision,
    geom geometry
);

CREATE TABLE derived.fim_channels_hi
(
    hydro_id integer PRIMARY KEY,
    huc6 text,
    fim_vers double precision,
    geom geometry
);

CREATE TABLE derived.fim_channels_prvi
(
    hydro_id integer PRIMARY KEY,
    huc6 text,
    fim_vers double precision,
    geom geometry
);

-- Create the max flows tables.
CREATE TABLE cache.max_flows_ana (
    feature_id integer,
    maxflow_1hour double precision
);
    
CREATE TABLE cache.max_flows_ana_hi (
    feature_id integer,
    maxflow_1hour double precision
);
    
CREATE TABLE cache.max_flows_ana_prvi (
    feature_id integer,
    maxflow_1hour double precision
);
    
CREATE TABLE cache.max_flows_mrf (
    feature_id integer,
    maxflow_3day double precision,
    maxflow_5day double precision,
    maxflow_10day double precision
);

CREATE TABLE cache.max_flows_srf (
    feature_id integer,
    maxflow_18hour double precision
);

CREATE TABLE cache.max_flows_srf_hi (
    feature_id integer,
    maxflow_48hour double precision
);

CREATE TABLE cache.max_flows_srf_prvi(
    feature_id integer,
    maxflow_48hour double precision
);
