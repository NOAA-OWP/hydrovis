SELECT 
    DISTINCT LPAD(huc8::text, 8, '0') as huc
FROM derived.featureid_huc_crosswalk
WHERE 
    coastal = 'pr'