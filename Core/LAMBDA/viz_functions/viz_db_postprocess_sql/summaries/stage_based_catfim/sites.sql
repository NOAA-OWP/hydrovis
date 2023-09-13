DROP TABLE IF EXISTS publish.stage_based_catfim_sites;

SELECT 
    base.*, 
    ST_TRANSFORM(station.geo_point, 3857) AS geom
INTO publish.stage_based_catfim_sites
FROM ingest.stage_based_catfim_sites AS base
LEFT JOIN external.nws_station AS station
    ON station.nws_station_id = base.nws_station_id;