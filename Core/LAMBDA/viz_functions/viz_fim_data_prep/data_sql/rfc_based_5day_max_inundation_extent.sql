WITH waterbody_reaches AS (SELECT feature_id
						   FROM ingest.rnr_max_flows
						   WHERE waterbody_status IS NOT null
						   GROUP BY feature_id
						  )
SELECT
    max_forecast.feature_id,
    round(max_forecast.streamflow::numeric, 2) as streamflow_cms,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id
FROM ingest.rnr_max_flows max_forecast
JOIN derived.fim4_featureid_crosswalk AS crosswalk ON max_forecast.feature_id = crosswalk.feature_id
LEFT OUTER JOIN waterbody_reaches ON max_forecast.feature_id = waterbody_reaches.feature_id
WHERE 
    viz_max_status IN ('action', 'minor', 'moderate', 'major', 'record') AND 
    waterbody_reaches.feature_id IS NULL AND
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999;