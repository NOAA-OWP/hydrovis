DROP TABLE IF EXISTS publish.srf_18hr_water_management;

SELECT
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
    srf.outflow,
    srf.water_sfc_elev,
    srf.reference_time
INTO publish.srf_18hr_water_management
FROM ingest.nwm_reservoir_srf as srf
JOIN derived.nwm_reservoirs as reservoirs ON reservoirs.lake_id = srf.feature_id;
