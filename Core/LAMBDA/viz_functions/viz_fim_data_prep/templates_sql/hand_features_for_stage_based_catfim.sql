WITH feature_streamflows as (
    {streamflow_sql}
)

SELECT
    crosswalk.feature_id,
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id,
    fs.stage_m,
    fs.nws_station_id
FROM derived.fim4_featureid_crosswalk AS crosswalk
JOIN feature_streamflows fs ON fs.feature_id = crosswalk.feature_id
LEFT JOIN {db_fim_table} r2f ON r2f.feature_id = crosswalk.feature_id
WHERE
    crosswalk.huc8 IS NOT NULL AND 
    crosswalk.lake_id = -999 AND
    r2f.feature_id IS NULL