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

-- CREATE FLOW_THRESHOLDS VIEW
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
	minor_stage as minor,
	moderate_stage as moderate,
	major_stage as major,
	record_stage as record
FROM external.threshold station
WHERE rating_source = 'NONE' 
	AND COALESCE(action_stage, minor_stage, moderate_stage, major_stage, record_stage) IS NOT NULL;