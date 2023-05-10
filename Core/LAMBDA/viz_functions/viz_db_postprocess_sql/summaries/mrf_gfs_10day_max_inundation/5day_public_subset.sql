DROP TABLE IF EXISTS publish.mrf_gfs_max_inundation_5day_public;

SELECT
    inun.feature_id_str,
    inun.geom,
    inun.streamflow_cfs,
    inun.reference_time
INTO publish.mrf_gfs_max_inundation_5day_public
FROM publish.mrf_gfs_max_inundation_5day as inun, derived.fim_domain as fim_domain
WHERE ST_Intersects(inun.geom, fim_domain.geom)