DROP TABLE IF EXISTS publish.rfc_based_5day_max_inundation_public;

SELECT
    inun.feature_id_str,
    inun.geom,
    inun.streamflow_cfs,
    inun.reference_time
INTO publish.rfc_based_5day_max_inundation_public
FROM publish.rfc_based_5day_max_inundation as inun, derived.fim_domain as fim_domain
WHERE ST_Intersects(inun.geom, fim_domain.geom)