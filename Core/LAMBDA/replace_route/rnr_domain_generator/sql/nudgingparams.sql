SELECT  
    LPAD(xwalk.hydro_id, 15) as "stationId"
FROM rnr.domain_routelink rl
LEFT JOIN rnr.domain_crosswalk xwalk
    ON xwalk.nwm_feature_id = rl.link
WHERE xwalk.hydro_id IS NOT NULL
ORDER BY order_index;