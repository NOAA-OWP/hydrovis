SELECT
    CONCAT(LPAD(crosswalk.huc8::text, 8, '0'), '-', crosswalk.branch_id) as huc8_branch,
    LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 6) as huc,
    crosswalk.hydro_id
FROM derived.fim4_featureid_crosswalk AS crosswalk
WHERE crosswalk.huc8 IS NOT NULL and crosswalk.branch_id != '0' and LEFT(LPAD(crosswalk.huc8::text, 8, '0'), 2) = '21'
ORDER BY crosswalk.huc8