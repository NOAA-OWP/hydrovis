-- This template is designed to add freshly processed FIM polygons to the cached_fim tables on Redshift

-- 1. Add unique feature_id/hydro_id records to the hydrotable_cached_max table
INSERT INTO fim.hydrotable_cached_max(hydro_id, feature_id, huc8, branch, fim_version, max_rc_discharge_cfs, max_rc_stage_ft)
SELECT
    fim.hydro_id,
    fim.feature_id,
    fim.huc8,
    fim.branch,
    fim.fim_version,
    fim.max_rc_discharge_cfs,
    fim.max_rc_stage_ft
FROM {postgis_fim_table} AS fim
LEFT OUTER JOIN fim.hydrotable_cached_max AS hcm ON fim.hydro_id = hcm.hydro_id AND fim.feature_id = hcm.feature_id AND fim.huc8 = hcm.huc8 AND fim.branch = hcm.branch
WHERE fim.prc_method = 'HAND_Processing' AND
hcm.hydro_id IS NULL
GROUP BY fim.hydro_id, fim.feature_id, fim.huc8, fim.branch, fim.fim_version, fim.max_rc_discharge_cfs, fim.max_rc_stage_ft;

-- 2. Add records for each step of the hydrotable to the hydrotable_cached table
INSERT INTO fim.hydrotable_cached (hydro_id, feature_id, huc8, branch, rc_discharge_cfs, rc_previous_discharge_cfs, rc_stage_ft, rc_previous_stage_ft)
SELECT
    fim.hydro_id,
    fim.feature_id,
    fim.huc8,
    fim.branch,
    fim.rc_discharge_cfs,
    fim.rc_previous_discharge_cfs,
    fim.rc_stage_ft,
    fim.rc_previous_stage_ft
FROM {postgis_fim_table} AS fim
LEFT OUTER JOIN fim.hydrotable_cached AS hc ON fim.hydro_id = hc.hydro_id AND fim.rc_stage_ft = hc.rc_stage_ft AND fim.feature_id = hc.feature_id AND fim.huc8 = hc.huc8 AND fim.branch = hc.branch
WHERE fim.prc_method = 'HAND_Processing' AND
hc.rc_stage_ft IS NULL;

-- 3. Add records for each subdivided part of the geometry to hydrotable_cached_geo table
INSERT INTO fim.hydrotable_cached_geo (hydro_id, feature_id, huc8, branch, rc_stage_ft, geom_part, geom)
SELECT
    fim.hydro_id,
    fim.feature_id,
    fim.huc8,
    fim.branch,
    fim.rc_stage_ft,
    fim.geom_part,
    ST_GeomFromText(geom_wkt)
FROM {postgis_fim_table}_geo_view AS fim
JOIN fim.hydrotable_cached_max AS hcm ON fim.hydro_id = hcm.hydro_id AND fim.feature_id = hcm.feature_id AND fim.huc8 = hcm.huc8 AND fim.branch = hcm.branch
LEFT OUTER JOIN fim.hydrotable_cached_geo AS hcg ON fim.hydro_id = hcg.hydro_id AND fim.rc_stage_ft = hcg.rc_stage_ft AND fim.feature_id = hcg.feature_id AND fim.huc8 = hcg.huc8 AND fim.branch = hcg.branch
WHERE hcg.rc_stage_ft IS NULL;

-- 4. Add records for zero_stage features to zero stage table
INSERT INTO fim.hydrotable_cached_zero_stage (hydro_id, feature_id, huc8, branch, rc_discharge_cms, note)
SELECT
    fim.hydro_id,
    fim.feature_id,
    fim.huc8,
    fim.branch,
    fim.rc_discharge_cms,
    fim.note
FROM {postgis_fim_table}_zero_stage AS fim
LEFT OUTER JOIN fim.hydrotable_cached_zero_stage AS hczs ON fim.hydro_id = hczs.hydro_id AND fim.feature_id = hczs.feature_id AND fim.huc8 = hczs.huc8 AND fim.branch = hczs.branch
WHERE hczs.rc_discharge_cms IS NULL;