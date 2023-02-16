DROP TABLE IF EXISTS publish.rfc_5day_max_downstream_streamflow_rfc_points;
SELECT
    ahps.nws_lid,
    usgs_sitecode,
    nws_name,
    to_char('1900-01-01 00:00:00'::timestamp without time zone, 'YYYY-MM-DD HH24:MI:SS UTC') AS reference_time,
    ST_SetSRID(ST_MakePoint( longitude, latitude), 4326) AS geom
INTO publish.rfc_5day_max_downstream_streamflow_rfc_points
FROM ingest.ahps_metadata ahps
INNER JOIN ingest.rnr_max_flows rfc ON ahps.nws_lid = rfc.nws_lid
GROUP BY ahps.nws_lid, usgs_sitecode, nws_name, geom