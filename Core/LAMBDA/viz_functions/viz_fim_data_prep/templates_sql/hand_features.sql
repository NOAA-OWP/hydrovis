WITH feature_streamflows as (
    {streamflow_sql}
)

SELECT
    fs.feature_id,
    CONCAT(LPAD(fs.huc8::text, 8, '0'), '-', fs.branch) as huc8_branch,
    LEFT(LPAD(fs.huc8::text, 8, '0'), 6) as huc,
    fs.hydro_id,
    fs.discharge_cms AS streamflow_cms --TODO: Update here and in lambda to discharge
FROM feature_streamflows fs
LEFT JOIN {db_fim_table} cf ON cf.feature_id = fs.feature_id AND cf.hydro_id = fs.hydro_id AND cf.huc8 = fs.huc8 AND cf.branch = fs.branch
LEFT JOIN {db_fim_table}_zero_stage zs ON zs.feature_id = fs.feature_id AND zs.hydro_id = fs.hydro_id AND zs.huc8 = fs.huc8 AND zs.branch = fs.branch
WHERE
    cf.fim_version IS NULL AND
    zs.rc_discharge_cms IS NULL