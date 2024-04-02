-- OPTIMIZE ROUTELINK TABLE (AFTER RAW FILE INGESTED)
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

-- OPTIMIZE LAKEPARM TABLE (AFTER RAW FILE INGESTED)
alter table rnr.nwm_lakeparm add order_index serial;
alter table rnr.nwm_lakeparm add primary key (lake_id);

-- CREATE STAGGERED USGS RATING CURVES TABLE
DROP TABLE IF EXISTS rnr.staggered_curves_usgs;

WITH valid_stations AS (
	SELECT DISTINCT nws_station_id
	FROM external.nws_station
	WHERE LENGTH(TRIM(nws_station_id)) = 5
		AND SUBSTRING(nws_station_id, 4, 1) = SUBSTRING(state, 1, 1)
		AND LOWER(nws_station_id) NOT LIKE '%test%'
	ORDER BY nws_station_id
),

station_gage_crosswalk AS (
	SELECT DISTINCT ON (xwalk.nws_station_id)
		xwalk.nws_station_id,
		xwalk.gage_id
	FROM external.full_crosswalk_view xwalk
	JOIN valid_stations ON valid_stations.nws_station_id = xwalk.nws_station_id
	WHERE xwalk.nws_station_id IS NOT NULL AND xwalk.gage_id IS NOT NULL
	ORDER BY 
		nws_station_id ASC,
		nws_usgs_crosswalk_dataset_id DESC NULLS LAST,
		location_nwm_crosswalk_dataset_id DESC NULLS LAST
),

station_usgs_curves AS (
	SELECT 
		xwalk.nws_station_id,
		curve.stage,
		curve.flow
	FROM station_gage_crosswalk xwalk
	JOIN external.rating rating
		ON rating.location_id = xwalk.gage_id
	JOIN external.rating_curve curve
		ON curve.rating_id = rating.rating_id
),

a AS (
	SELECT *, row_number() over (ORDER BY nws_station_id, stage) as row_num FROM station_usgs_curves
)

SELECT
	a.nws_station_id,
	a.stage,
	b.stage as next_higher_point_stage,
	a.flow,
	b.flow as next_higher_point_flow
INTO rnr.staggered_curves_usgs
FROM a
LEFT JOIN a AS b
	ON b.nws_station_id = a.nws_station_id
	AND b.row_num = a.row_num + 1;

-- CREATE STAGGERED NRLDB RATING CURVES TABLE
DROP TABLE IF EXISTS rnr.staggered_curves_nrldb;

WITH valid_stations AS (
	SELECT nws_station_id
	FROM external.nws_station
	WHERE LENGTH(TRIM(nws_station_id)) = 5
		AND SUBSTRING(nws_station_id, 4, 1) = SUBSTRING(state, 1, 1)
		AND LOWER(nws_station_id) NOT LIKE '%test%'
	ORDER BY nws_station_id
),

a AS (
	SELECT 
		*, 
		row_number() over (ORDER BY location_id, stage) as row_num 
	FROM external.nrldb_rating_curve curve
	JOIN valid_stations ON valid_stations.nws_station_id = curve.location_id
)

SELECT
	a.location_id as nws_station_id,
	a.stage,
	b.stage as next_higher_point_stage,
	a.flow,
	b.flow as next_higher_point_flow
INTO rnr.staggered_curves_nrldb
FROM a
LEFT JOIN a AS b
	ON b.location_id = a.location_id
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

-- CREATE FLOW_THRESHOLDS VIEW
-- Officially in Core\EC2\RDSBastion\scripts\utils\setup_foreign_tables.tftpl (for automatic execution on deployment), but duplicated here for reference
DROP VIEW IF EXISTS rnr.flow_thresholds;
CREATE VIEW rnr.flow_thresholds AS

WITH

main AS (
	SELECT 
		station.location_id as nws_station_id,
		COALESCE(native.action_flow, usgs.action_flow_calc, nrldb.action_flow_calc) as action,
			CASE 
				WHEN native.action_flow IS NOT NULL
				THEN 'Native'
				WHEN usgs.action_flow_calc IS NOT NULL
				THEN 'USGS'
				WHEN nrldb.action_flow_calc IS NOT NULL
				THEN 'NRLDB'
			END as action_source,
			COALESCE(native.minor_flow, usgs.minor_flow_calc, nrldb.minor_flow_calc) as minor,
			CASE 
				WHEN native.minor_flow IS NOT NULL
				THEN 'Native'
				WHEN usgs.minor_flow_calc IS NOT NULL
				THEN 'USGS'
				WHEN nrldb.minor_flow_calc IS NOT NULL
				THEN 'NRLDB'
			END as minor_source,
			COALESCE(native.moderate_flow, usgs.moderate_flow_calc, nrldb.moderate_flow_calc) as moderate,
			CASE 
				WHEN native.moderate_flow IS NOT NULL
				THEN 'Native'
				WHEN usgs.moderate_flow_calc IS NOT NULL
				THEN 'USGS'
				WHEN nrldb.moderate_flow_calc IS NOT NULL
				THEN 'NRLDB'
			END as moderate_source,
			COALESCE(native.major_flow, usgs.major_flow_calc, nrldb.major_flow_calc) as major,
			CASE 
				WHEN native.major_flow IS NOT NULL
				THEN 'Native'
				WHEN usgs.major_flow_calc IS NOT NULL
				THEN 'USGS'
				WHEN nrldb.major_flow_calc IS NOT NULL
				THEN 'NRLDB'
			END as major_source,
			COALESCE(native.record_flow, usgs.record_flow_calc, nrldb.record_flow_calc) as record,
			CASE 
				WHEN native.record_flow IS NOT NULL
				THEN 'Native'
				WHEN usgs.record_flow_calc IS NOT NULL
				THEN 'USGS'
				WHEN nrldb.record_flow_calc IS NOT NULL
				THEN 'NRLDB'
			END as record_source
	FROM (SELECT DISTINCT location_id FROM external.threshold) AS station
	LEFT JOIN external.threshold native
		ON native.location_id = station.location_id 
		AND native.rating_source = 'NONE'
	LEFT JOIN external.threshold usgs
		ON usgs.location_id = station.location_id 
		AND usgs.rating_source = 'USGS Rating Depot'
	LEFT JOIN external.threshold nrldb
		ON nrldb.location_id = station.location_id 
		AND nrldb.rating_source = 'NRLDB'
)

SELECT * FROM main
WHERE COALESCE(action, minor, moderate, major, record) IS NOT NULL;

-- CREATE STAGE THRESHOLDS VIEW
-- Officially in Core\EC2\RDSBastion\scripts\utils\setup_foreign_tables.tftpl (for automatic execution on deployment), but duplicated here for reference
DROP VIEW IF EXISTS rnr.stage_thresholds;
CREATE VIEW rnr.stage_thresholds AS

WITH

native_stage_thresholds AS (
	SELECT 
		location_id,
		action_stage,
		minor_stage,
		moderate_stage,
		major_stage,
		record_stage
	FROM external.threshold
	WHERE rating_source = 'NONE'
)

SELECT 
	location_id AS nws_station_id,
	action_stage as action,
	'Native' as action_source,
	minor_stage as minor,
	'Native' as minor_source,
	moderate_stage as moderate,
	'Native' as moderate_source,
	major_stage as major,
	'Native' as major_source,
	record_stage as record,
	'Native' as record_source
FROM external.threshold station
WHERE rating_source = 'NONE' 
	AND COALESCE(action_stage, minor_stage, moderate_stage, major_stage, record_stage) IS NOT NULL;