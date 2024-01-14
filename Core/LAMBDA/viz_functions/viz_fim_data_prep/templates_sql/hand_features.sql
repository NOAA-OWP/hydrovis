SELECT
    fs.hand_id,
    fs.feature_id,
    CONCAT(LPAD(fs.huc8::text, 8, '0'), '-', fs.branch) as huc8_branch,
    LEFT(LPAD(fs.huc8::text, 8, '0'), 6) as huc,
    fs.hydro_id,
    fs.discharge_cms AS streamflow_cms --TODO: Update here and in lambda to discharge
FROM {db_fim_table}_flows fs
LEFT JOIN {db_fim_table} fim ON fim.hand_id = fs.hand_id
LEFT JOIN {db_fim_table}_zero_stage zs ON zs.hand_id = fs.hand_id
WHERE
    fim.fim_version IS NULL AND
    zs.rc_discharge_cms IS NULL