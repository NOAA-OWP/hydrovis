-- We'll temporarily increase work_mem to 512MB, to help with performance on PostGIS spatial joins (default is 4MB)
SET work_mem TO '512MB';
--------------- Building Footprints ---------------
DROP TABLE IF EXISTS publish.ana_inundation_building_footprints_hi;
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
    flows.hydro_id,
	flows.hydro_id::TEXT AS hydro_id_str,
	flows.feature_id,
	flows.feature_id::TEXT AS feature_id_str,
	flows.discharge_cfs AS streamflow_cfs,
	fim.rc_stage_ft AS fim_stage_ft,
    buildings.geom,
	ST_Centroid(buildings.geom) as geom_xy
INTO publish.ana_inundation_building_footprints_hi
FROM external.building_footprints_fema as buildings
JOIN fim_ingest.ana_inundation_hi_geo fim_geo ON ST_INTERSECTS(fim_geo.geom, buildings.geom)
JOIN fim_ingest.ana_inundation_hi_flows flows ON fim_geo.hand_id = flows.hand_id
JOIN fim_ingest.ana_inundation_hi fim ON fim_geo.hand_id = fim.hand_id;

--------------- County Summary ---------------
DROP TABLE IF EXISTS publish.ana_inundation_counties_hi;
SELECT
	counties.geoid,
	counties.name as county,
	buildings.prop_st as state,
	max(fim.streamflow_cfs) AS max_flow_cfs,
	avg(fim.streamflow_cfs) AS avg_flow_cfs,
	max(fim.fim_stage_ft) AS max_fim_stage_ft,
	avg(fim.fim_stage_ft) AS avg_fim_stage_ft,
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
INTO publish.ana_inundation_counties_hi
FROM derived.counties AS counties
JOIN derived.channels_county_crosswalk AS crosswalk ON counties.geoid = crosswalk.geoid
JOIN publish.ana_inundation_hi AS fim on crosswalk.feature_id = fim.feature_id
JOIN publish.ana_inundation_building_footprints_hi AS buildings ON crosswalk.feature_id = buildings.feature_id
GROUP BY counties.geoid, counties.name, counties.geom, buildings.prop_st;

INSERT INTO publish.ana_inundation_counties_hi(
	geoid, county, state, max_flow_cfs, avg_flow_cfs, max_fim_stage_ft, avg_fim_stage_ft, buildings_impacted, building_sqft_impacted, bldgs_agriculture, bldgs_assembly, bldgs_commercial, bldgs_education, bldgs_government, bldgs_industrial, bldgs_residential, bldgs_utility_msc, bldgs_other, reference_time, update_time, geom)
	VALUES (NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL, to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), to_char(now()::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC'), NULL);