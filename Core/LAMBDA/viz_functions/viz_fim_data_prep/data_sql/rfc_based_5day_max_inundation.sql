SELECT
	rnr.feature_id,
	streamflow_cms,
    CONCAT(LPAD(xwalk.huc8::text, 8, '0'), '-', xwalk.branch_id) as huc8_branch,
    LEFT(LPAD(xwalk.huc8::text, 8, '0'), 6) as huc,
    xwalk.hydro_id
FROM publish.rfc_based_5day_max_streamflow rnr
JOIN derived.fim4_featureid_crosswalk xwalk 
	ON xwalk.feature_id = rnr.feature_id
WHERE is_waterbody = 'no'
	AND is_downstream_of_waterbody = 'no'
	AND viz_status IN ('Action', 'Minor', 'Moderate', 'Major')
	AND xwalk.huc8 IS NOT NULL
	AND xwalk.lake_id = -999;