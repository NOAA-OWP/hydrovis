-- This template is designed to add freshly processed FIM polygons (which don't already exist in the cache) in the current FIM run back into to the cached hand tables.
-- To ensure that no duplicates are added to the cache (which could be possible if multiple fim configurations are running at the same time), this query joins to the target table and ensures that
-- the current hydrotable record doesn't alraedy exist in the cache.

-- 1. Add unique hand_id records to the hydrotable_cached_max table
INSERT INTO fim_cache.hand_hydrotable_cached_max(hand_id, fim_version, max_rc_discharge_cfs, max_rc_stage_ft)
SELECT
    fim.hand_id,
    fim.fim_version,
    fim.max_rc_discharge_cfs,
    fim.max_rc_stage_ft
FROM {db_fim_table} AS fim
LEFT OUTER JOIN fim_cache.hand_hydrotable_cached_max AS hcm ON fim.hand_id = hcm.hand_id
WHERE fim.prc_method = 'HAND_Processing' AND
hcm.hand_id IS NULL
GROUP BY fim.hand_id, fim.fim_version, fim.max_rc_discharge_cfs, fim.max_rc_stage_ft;

-- 2. Add records for each stage_ft step of the hydrotable to the hydrotable_cached table
INSERT INTO fim_cache.hand_hydrotable_cached (hand_id, rc_discharge_cfs, rc_previous_discharge_cfs, rc_stage_ft, rc_previous_stage_ft)
SELECT
    fim.hand_id,
    fim.rc_discharge_cfs,
    fim.rc_previous_discharge_cfs,
    fim.rc_stage_ft,
    fim.rc_previous_stage_ft
FROM {db_fim_table} AS fim
LEFT OUTER JOIN fim_cache.hand_hydrotable_cached AS hc ON fim.hand_id = hc.hand_id AND fim.rc_stage_ft = hc.rc_stage_ft
WHERE fim.prc_method = 'HAND_Processing' AND
hc.rc_stage_ft IS NULL;

-- 3. Add records for each geometry to hydrotable_cached_geo table
INSERT INTO fim_cache.hand_hydrotable_cached_geo (hand_id, rc_stage_ft, geom)
SELECT
    fim_geo.hand_id,
    fim_geo.rc_stage_ft,
    fim_geo.geom
FROM {db_fim_table}_geo AS fim_geo
JOIN {db_fim_table} AS fim ON fim_geo.hand_id = fim.hand_id
LEFT OUTER JOIN fim_cache.hand_hydrotable_cached_geo AS hcg ON fim_geo.hand_id = hcg.hand_id AND fim_geo.rc_stage_ft = hcg.rc_stage_ft
WHERE fim.prc_method = 'HAND_Processing' AND hcg.rc_stage_ft IS NULL;

-- 4. Add records for zero_stage features to zero stage table
INSERT INTO fim_cache.hand_hydrotable_cached_zero_stage (hand_id, rc_discharge_cms, note)
SELECT
    fim.hand_id,
    fim.rc_discharge_cms,
    fim.note
FROM {db_fim_table}_zero_stage AS fim
LEFT OUTER JOIN fim_cache.hand_hydrotable_cached_zero_stage AS hczs ON fim.hand_id = hczs.hand_id
WHERE hczs.rc_discharge_cms IS NULL;