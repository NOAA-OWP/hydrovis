SELECT
    rf.feature_id,
    ROUND(CAST(rf.high_water_threshold * 0.0283168 as numeric), 2) as streamflow_cms
FROM derived.recurrence_flows_conus rf