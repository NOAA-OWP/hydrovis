SELECT
	rnr.feature_id,
	streamflow_cms
FROM publish.rfc_based_5day_max_streamflow rnr
WHERE is_waterbody = 'no'
	AND is_downstream_of_waterbody = 'no'
	AND viz_status IN ('Action', 'Minor', 'Moderate', 'Major')