-- CREATE FOREIGN SERVER MAPPING FOR WRDS/INGEST rfcfcst DB
DROP SCHEMA IF EXISTS rfcfcst;
CREATE schema rfcfcst;
DROP SERVER IF EXISTS wrds_rfcfcst CASCADE;
CREATE SERVER wrds_rfcfcst FOREIGN DATA WRAPPER postgres_fdw OPTIONS (host 'hydrovis-ti-ingest.c4vzypepnkx3.us-east-1.rds.amazonaws.com', dbname 'rfcfcst', port '5432');
CREATE USER MAPPING FOR viz_proc_dev_rw_user SERVER wrds_rfcfcst OPTIONS (user 'rfc_fcst_user', password 'urkZ6DiRqC4jRPjX6sbAnx8Nq');
CREATE USER MAPPING FOR viz_proc_admin_rw_user SERVER wrds_rfcfcst OPTIONS (user 'rfc_fcst_user', password 'urkZ6DiRqC4jRPjX6sbAnx8Nq');
CREATE USER MAPPING FOR postgres SERVER wrds_rfcfcst OPTIONS (user 'rfc_fcst_user', password 'urkZ6DiRqC4jRPjX6sbAnx8Nq');
IMPORT FOREIGN SCHEMA public EXCEPT (django_migrations, forecast_values_latest, forecast_values_load, hml, hml_log, hml_xml, hml_xml_log) FROM SERVER wrds_rfcfcst INTO rfcfcst;
ALTER SERVER wrds_rfcfcst OPTIONS (fetch_size '150000');

-- OPTIMIZE ROUTELINK TABLE
alter table rnr.nwm_routelink add order_index serial;
alter table rnr.nwm_routelink add primary key (link);

alter table rnr.nwm_routelink add to_ int;

update rnr.nwm_routelink AS one
set to_ = two.link
from rnr.nwm_routelink AS two
where one.to = two.link;

alter table rnr.nwm_routelink drop column "to";
alter table rnr.nwm_routelink RENAME COLUMN to_ to "to";

alter table rnr.nwm_routelink add constraint fk_self foreign key ("to") references rnr.nwm_routelink;

-- OPTIMIZE LAKEPARM TABLE
alter table rnr.nwm_lakeparm add order_index serial;
alter table rnr.nwm_lakeparm add primary key (lake_id);

-- CREATE STAGGERED RATING CURVES TABLE
WITH a AS (
	SELECT *, row_number() over (ORDER BY rating_id, stage) as row_num FROM external.rating_curve
)
SELECT
	a.rating_id,
	a.stage,
	b.stage as next_higher_point_stage,
	a.flow,
	b.flow as next_higher_point_flow
INTO rnr.staggered_curves
FROM a
LEFT JOIN a AS b
	ON b.rating_id = a.rating_id
	AND b.row_num = a.row_num + 1;

-- CREATE VIZ-OFFICIAL CROSSWALK TABLE
SELECT DISTINCT ON (nwm_feature_id, nws_station_id) 
	* 
INTO rnr.nwm_crosswalk
FROM external.full_crosswalk_view xwalk 
ORDER BY 
	nwm_feature_id, 
	nws_station_id,
	nws_usgs_crosswalk_dataset_id DESC NULLS LAST,
	location_nwm_crosswalk_dataset_id DESC NULLS LAST;