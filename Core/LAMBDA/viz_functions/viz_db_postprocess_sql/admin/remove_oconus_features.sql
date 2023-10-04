DELETE FROM {target_table} t1
WHERE EXISTS(SELECT 1 FROM derived.oconus_features t2 Where t1.feature_id = t2.feature_id)