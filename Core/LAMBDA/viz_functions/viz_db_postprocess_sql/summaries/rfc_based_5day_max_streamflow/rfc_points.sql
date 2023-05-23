DROP TABLE IF EXISTS publish.rfc_based_5day_max_streamflow_rfc_points;
SELECT DISTINCT ON (ahps.nws_lid)
    ahps.nws_lid,
    usgs_sitecode,
    nws_name,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    ST_TRANSFORM(ST_SetSRID(ST_MakePoint(longitude, latitude),4326),3857) as geom
INTO publish.rfc_based_5day_max_streamflow_rfc_points
FROM ingest.ahps_metadata ahps
INNER JOIN publish.rfc_based_5day_max_streamflow rfc ON ahps.nws_lid = rfc.nws_station_id