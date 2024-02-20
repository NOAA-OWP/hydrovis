DROP TABLE IF EXISTS publish.rfc_based_5day_max_streamflow_rfc_points;

SELECT DISTINCT ON (main.nws_station_id)
    main.nws_station_id as nws_lid,
    main.gage_id as usgs_sitecode,
    station.name as nws_name,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    ST_TRANSFORM(station.geo_point, 3857) as geom
INTO publish.rfc_based_5day_max_streamflow_rfc_points
FROM rnr.domain_crosswalk as main
LEFT JOIN external.nws_station as station on station.nws_station_id = main.nws_station_id
WHERE main.nws_station_id IS NOT NULL;