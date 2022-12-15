#!/bin/bash

db_instance_tag=$1
db_name=$2
task_token=$3
task_region=$4

if [ "$db_instance_tag" == "egis" ]; then
  export PGUSER="${EGIS_PGUSER}"
  export PGPASSWORD="${EGIS_PGPASSWORD}"
  export PGHOST="${EGIS_PGHOST}"
  export PGPORT="${EGIS_PGPORT}"
elif [ "$db_instance_tag" == "ingest" ]; then
  export PGUSER="${INGEST_PGUSER}"
  export PGPASSWORD="${INGEST_PGPASSWORD}"
  export PGHOST="${INGEST_PGHOST}"
  export PGPORT="${INGEST_PGPORT}"
elif [ "$db_instance_tag" == "viz" ]; then
  export PGUSER="${VIZ_PGUSER}"
  export PGPASSWORD="${VIZ_PGPASSWORD}"
  export PGHOST="${VIZ_PGHOST}"
  export PGPORT="${VIZ_PGPORT}"
fi

psql -c "DROP DATABASE IF EXISTS ${db_name}_retired" && \
psql -c "SELECT pg_terminate_backend(pg_stat_activity.pid) 
         FROM pg_stat_activity 
         WHERE pg_stat_activity.datname = '$db_name' AND pid <> pg_backend_pid(); 
         
         ALTER DATABASE $db_name RENAME TO ${db_name}_retired; 
         ALTER DATABASE ${db_name}_ondeck RENAME TO $db_name; 
         GRANT CONNECT ON DATABASE $db_name TO rfc_fcst_ro_user, location_ro_user, nwm_viz_ro; 
         GRANT SELECT ON ALL TABLES IN SCHEMA public TO rfc_fcst_ro_user, location_ro_user, nwm_viz_ro;"

status=$?

if [ -n "$task_token" ]; then
  if [ $status -eq 0 ]; then
    aws stepfunctions send-task-success --region $task_region --task-token "$task_token" --task-output '{"success": true}'
  else
    aws stepfunctions send-task-failure --region $task_region --task-token "$task_token"
  fi
else
  return $status
fi