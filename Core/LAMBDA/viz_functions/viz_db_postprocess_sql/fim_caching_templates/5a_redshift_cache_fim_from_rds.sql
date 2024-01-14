-- This template is designed to add freshly processed FIM polygons (which don't already exist in the cache) in the current FIM run back into to the cached hand tables on Redshift.
-- To ensure that no duplicates are added to the cache (which could be possible if multiple fim configurations are running at the same time), this query joins to the target table and ensures that
-- the current hydrotable record doesn't alraedy exist in the cache. This slows down the query significantly, and there is likely a potential optimization here... possibly using the UPSERT functionality of Redshift.
-- As of right now, feature_id, hydro_id, huc8, branch, and stage combine to represent a primary key in the hand hydrotables, so all of those fields are used in joins
-- (I've asked the fim team to hash a single unique id for feature_id, hydro_id, huc8, branch combinations... which will simplify these queries, and hopefully help with performance.

-- 1. Add unique feature_id/hydro_id records to the hydrotable_cached_max table
INSERT INTO fim.hydrotable_cached_max(hand_id, hydro_id, feature_id, huc8, branch, fim_version, max_rc_discharge_cfs, max_rc_stage_ft)
SELECT
    fim.hand_id,
    fim.fim_version,
    fim.max_rc_discharge_cfs,
    fim.max_rc_stage_ft
FROM {postgis_fim_table} AS fim
LEFT OUTER JOIN fim.hydrotable_cached_max AS hcm ON fim.hand_id = hcm.hand_id
WHERE fim.prc_method = 'HAND_Processing' AND
hcm.hydro_id IS NULL
GROUP BY fim.hand_id, fim.fim_version, fim.max_rc_discharge_cfs, fim.max_rc_stage_ft;

-- 2. Add records for each step of the hydrotable to the hydrotable_cached table
INSERT INTO fim.hydrotable_cached (hand_id, rc_discharge_cfs, rc_previous_discharge_cfs, rc_stage_ft, rc_previous_stage_ft)
SELECT
    fim.hand_id,
    fim.rc_discharge_cfs,
    fim.rc_previous_discharge_cfs,
    fim.rc_stage_ft,
    fim.rc_previous_stage_ft
FROM {postgis_fim_table} AS fim
LEFT OUTER JOIN fim.hydrotable_cached AS hc ON fim.hand_id = hc.hand_id AND fim.rc_stage_ft = hc.rc_stage_ft
WHERE fim.prc_method = 'HAND_Processing' AND
hc.rc_stage_ft IS NULL;

-- 3. Add records for each subdivided part of the geometry to hydrotable_cached_geo table
INSERT INTO fim.hydrotable_cached_geo (hand_id, rc_stage_ft, geom_part, geom)
SELECT
    fim.hand_id,
    fim.rc_stage_ft,
    fim.geom_part,
    ST_GeomFromText(geom_wkt)
FROM {postgis_fim_table}_geo_view AS fim
LEFT OUTER JOIN fim.hydrotable_cached_geo AS hcg ON fim.hand_id = hcg.hand_id AND fim.rc_stage_ft = hcg.rc_stage_ft
WHERE hcg.rc_stage_ft IS NULL;

-- 4. Add records for zero_stage features to zero stage table
INSERT INTO fim.hydrotable_cached_zero_stage (hand_id, rc_discharge_cms, note)
SELECT
    fim.hand_id,
    fim.rc_discharge_cms,
    fim.note
FROM {postgis_fim_table}_zero_stage AS fim
LEFT OUTER JOIN fim.hydrotable_cached_zero_stage AS hczs ON fim.hand_id = hczs.hand_id
WHERE hczs.rc_discharge_cms IS NULL;