--------------- Building Footprints ---------------
DROP TABLE IF EXISTS publish.srf_max_inundation_building_footprints_hi;
SELECT
	buildings.build_id,
    buildings.occ_cls,
    buildings.prim_occ,
    buildings.prop_st,
    buildings.sqfeet,
    buildings.height,
    buildings.censuscode,
    buildings.prod_date,
    buildings.source,
    buildings.val_method,
    fim.hydro_id,
	fim.feature_id,
	fim.streamflow_cfs,
	fim.hand_stage_ft,
    buildings.geom,
	ST_Centroid(buildings.geom) as geom_xy
INTO publish.srf_max_inundation_building_footprints_hi
FROM external.building_footprints_fema as buildings
JOIN publish.srf_max_inundation_hi fim ON ST_INTERSECTS(fim.geom, buildings.geom);

--------------- County Summary ---------------
DROP TABLE IF EXISTS publish.srf_max_inundation_counties_hi;
SELECT
	counties.geoid,
	counties.name as county,
	buildings.prop_st as state,
	max(fim.streamflow_cfs) AS max_flow_cfs,
	avg(fim.streamflow_cfs) AS avg_flow_cfs,
	max(fim.hand_stage_ft) AS max_interpolated_stage_ft,
	avg(fim.hand_stage_ft) AS avg_interpolated_stage_ft,
	sum(st_area(fim.geom))* 0.00000038610 AS flooded_area_sqmi,
	count(buildings.build_id) AS buildings_impacted,
	sum(buildings.sqfeet) AS building_sqft_impacted,
	sum(CASE WHEN buildings.occ_cls = 'Agriculture' THEN 1 ELSE 0 END) AS bldgs_agriculture,
	sum(CASE WHEN buildings.occ_cls = 'Assembly' THEN 1 ELSE 0 END) AS bldgs_assembly,
	sum(CASE WHEN buildings.occ_cls = 'Commercial' THEN 1 ELSE 0 END) AS bldgs_commercial,
	sum(CASE WHEN buildings.occ_cls = 'Education' THEN 1 ELSE 0 END) AS bldgs_education,
	sum(CASE WHEN buildings.occ_cls = 'Government' THEN 1 ELSE 0 END) AS bldgs_government,
	sum(CASE WHEN buildings.occ_cls = 'Industrial' THEN 1 ELSE 0 END) AS bldgs_industrial,
	sum(CASE WHEN buildings.occ_cls = 'Residential' THEN 1 ELSE 0 END) AS bldgs_residential,
	sum(CASE WHEN buildings.occ_cls = 'Utility and Misc' THEN 1 ELSE 0 END) AS bldgs_utility_msc,
	sum(CASE WHEN buildings.occ_cls = 'Other' THEN 1 WHEN buildings.occ_cls = 'Unclassified' THEN 1 WHEN buildings.occ_cls IS NULL THEN 1 ELSE 0 END) AS bldgs_other,
	to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
	to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS update_time,
	counties.geom
INTO publish.srf_max_inundation_counties_hi
FROM derived.counties AS counties
JOIN derived.channels_county_crosswalk AS crosswalk ON counties.geoid = crosswalk.geoid
JOIN publish.srf_max_inundation_hi AS fim on crosswalk.feature_id = fim.feature_id
JOIN publish.srf_max_inundation_building_footprints_hi AS buildings ON crosswalk.feature_id = buildings.feature_id
GROUP BY counties.geoid, counties.name, counties.geom, buildings.prop_st;