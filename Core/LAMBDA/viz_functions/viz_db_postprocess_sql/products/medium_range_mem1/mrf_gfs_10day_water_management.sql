DROP TABLE IF EXISTS publish.mrf_gfs_10day_water_management;

WITH initial_outflow AS (
    SELECT DISTINCT ON (mrf.feature_id)
        mrf.feature_id,
        mrf.feature_id::text as feature_id_str,
        CASE
            WHEN reservoir_type = 1
            THEN 'Level Pool'
            WHEN reservoir_type = 2
            THEN 'RFC'
            WHEN reservoir_type = 3
            THEN 'USACE'
            WHEN reservoir_type = 4
            THEN 'USGS'
        END as reservoir_type,
        ROUND((mrf.water_sfc_elev) * 3.28084) AS init_water_sfc_elev_ft,
        mrf.reference_time,
        reservoirs.geom
    FROM ingest.nwm_reservoir_mrf AS mrf
    JOIN derived.nwm_reservoirs as reservoirs ON reservoirs.lake_id = mrf.feature_id
    ORDER BY
        mrf.feature_id,
        mrf.forecast_hour
),
max_outflow AS (
    SELECT DISTINCT ON (mrf.feature_id)
        mrf.feature_id,
        ROUND((mrf.outflow) * 35.515) AS max_outflow_cfs
    FROM ingest.nwm_reservoir_mrf AS mrf
    ORDER BY
        mrf.feature_id,
        mrf.outflow DESC
)

SELECT
    init.feature_id,
    init.feature_id_str,
    init.reservoir_type,
    init.init_water_sfc_elev_ft,
    max.max_outflow_cfs,
    init.reference_time,
    init.geom
INTO publish.mrf_gfs_10day_water_management
FROM initial_outflow as init
JOIN max_outflow as max ON max.feature_id = init.feature_id;
