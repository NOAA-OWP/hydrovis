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