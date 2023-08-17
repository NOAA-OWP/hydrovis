SELECT 
    rl.*, 
    CASE 
        WHEN xwalk.hydro_id IS NOT NULL
        THEN LPAD(xwalk.hydro_id, 15)
        ELSE LPAD('', 15)
    END as gages_trim
FROM rnr.domain_routelink rl
LEFT JOIN rnr.domain_crosswalk xwalk
    ON xwalk.nwm_feature_id = rl.link
ORDER BY order_index;