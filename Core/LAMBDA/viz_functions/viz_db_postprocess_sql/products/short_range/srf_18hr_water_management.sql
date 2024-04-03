DROP TABLE IF EXISTS publish.srf_18hr_water_management;

WITH initial_outflow AS (
    SELECT DISTINCT ON (srf.feature_id)
        srf.feature_id,
        srf.feature_id::text as feature_id_str,
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
        srf.water_sfc_elev AS init_water_sfc_elev,
        srf.reference_time
    FROM ingest.nwm_reservoir_srf AS srf
    JOIN derived.nwm_reservoirs as reservoirs ON reservoirs.lake_id = srf.feature_id
    ORDER BY
        srf.feature_id,
        srf.forecast_hour
),
max_outflow AS (
    SELECT DISTINCT ON (srf.feature_id)
        srf.feature_id,
        srf.outflow AS max_outflow
    FROM ingest.nwm_reservoir_srf AS srf
    ORDER BY
        srf.feature_id,
        srf.outflow DESC
)

SELECT
    init.feature_id,
    init.feature_id_str,
    init.reservoir_type,
    init.init_water_sfc_elev,
    max.max_outflow,
    init.reference_time
FROM initial_outflow as init
JOIN max_outflow as max ON max.feature_id = init.feature_id;
