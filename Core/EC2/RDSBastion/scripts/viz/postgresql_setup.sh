#!/bin/bash

echo "---- SETTING UP VIZ DB ----"

VIZDBNAME="${VIZDBNAME}"
VIZDBHOST="${VIZDBHOST}"
VIZDBPORT=${VIZDBPORT}
VIZDBUSERNAME="${VIZDBUSERNAME}"
VIZDBPASSWORD="${VIZDBPASSWORD}"
EGISDBNAME="${EGISDBNAME}"
EGISDBHOST="${EGISDBHOST}"
EGISDBPORT=${EGISDBPORT}
EGISDBUSERNAME="${EGISDBUSERNAME}"
EGISDBPASSWORD="${EGISDBPASSWORD}"
DEPLOYMENT_BUCKET="${DEPLOYMENT_BUCKET}"
HOME="${HOME}"

### install postgresql ###
sudo yum install -y postgresql12

export PGPASSWORD=$${VIZDBPASSWORD}

# Adding postgis extension
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/ingest/database/postgis_setup.sql" "$${HOME}/postgis_setup.sql"
psql -h "$${VIZDBHOST}" -U "$${VIZDBUSERNAME}" -p $${VIZDBPORT} -d "$${VIZDBNAME}" -f "$${HOME}/postgis_setup.sql"
rm "$${HOME}/postgis_setup.sql"

# Cleaning up DB
echo "Cleaning up Viz DB..."
psql -h "$${VIZDBHOST}" -U "$${VIZDBUSERNAME}" -p $${VIZDBPORT} -d "$${VIZDBNAME}" -c "DROP SCHEMA IF EXISTS admin CASCADE; DROP SCHEMA IF EXISTS ingest CASCADE; DROP SCHEMA IF EXISTS derived CASCADE; DROP SCHEMA IF EXISTS fim CASCADE; DROP SCHEMA IF EXISTS cache CASCADE; DROP SCHEMA IF EXISTS publish CASCADE;"

echo "Setting up admin schema in the VIZ DB..."
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/viz/db_pipeline/db_dumps/vizDB_admin.dump" "$${HOME}/vizDB_admin.dump"
pg_restore -h "$${VIZDBHOST}" -p $${VIZDBPORT} -d "$${VIZDBNAME}" -U $${VIZDBUSERNAME} -j 4 -v "$${HOME}/vizDB_admin.dump"
rm "$${HOME}/vizDB_admin.dump"

echo "Setting up cache schema in the VIZ DB..."
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/viz/db_pipeline/db_dumps/vizDB_cache.dump" "$${HOME}/vizDB_cache.dump"
pg_restore -h "$${VIZDBHOST}" -p $${VIZDBPORT} -d "$${VIZDBNAME}" -U $${VIZDBUSERNAME} -j 4 -v "$${HOME}/vizDB_cache.dump"
rm "$${HOME}/vizDB_cache.dump"

echo "Setting up derived schema in the VIZ DB..."
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/viz/db_pipeline/db_dumps/vizDB_derived.dump" "$${HOME}/vizDB_derived.dump"
pg_restore -h "$${VIZDBHOST}" -p $${VIZDBPORT} -d "$${VIZDBNAME}" -U $${VIZDBUSERNAME} -j 4 -v "$${HOME}/vizDB_derived.dump"
rm "$${HOME}/vizDB_derived.dump"

echo "Setting up simplified fim schema in the VIZ DB..."
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/viz/db_pipeline/db_dumps/vizDB_fim_simplified.dump" "$${HOME}/vizDB_fim_simplified.dump"
pg_restore -h "$${VIZDBHOST}" -p $${VIZDBPORT} -d "$${VIZDBNAME}" -U $${VIZDBUSERNAME} -j 4 -v "$${HOME}/vizDB_fim_simplified.dump"
rm "$${HOME}/vizDB_fim_simplified.dump"

echo "Setting up ingest schema in the VIZ DB..."
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/viz/db_pipeline/db_dumps/vizDB_ingest.dump" "$${HOME}/vizDB_ingest.dump"
pg_restore -h "$${VIZDBHOST}" -p $${VIZDBPORT} -d "$${VIZDBNAME}" -U $${VIZDBUSERNAME} -j 4 -v "$${HOME}/vizDB_ingest.dump"
rm "$${HOME}/vizDB_ingest.dump"

echo "Setting up publish schema in the VIZ DB..."
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/viz/db_pipeline/db_dumps/vizDB_publish.dump" "$${HOME}/vizDB_publish.dump"
pg_restore -h "$${VIZDBHOST}" -p $${VIZDBPORT} -d "$${VIZDBNAME}" -U $${VIZDBUSERNAME} -j 4 -v "$${HOME}/vizDB_publish.dump"
rm "$${HOME}/vizDB_publish.dump"

# Setting up EGIS DB
export PGPASSWORD=$${EGISDBPASSWORD}

aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/ingest/database/postgis_setup.sql" "$${HOME}/postgis_setup.sql"
psql -h "$${EGISDBHOST}" -U "$${EGISDBUSERNAME}" -p $${EGISDBPORT} -d "$${EGISDBNAME}" -f "$${HOME}/postgis_setup.sql"
rm "$${HOME}/postgis_setup.sql"

# Cleaning up DB
echo "Cleaning up EGIS DB..."
psql -h "$${EGISDBHOST}" -U "$${EGISDBUSERNAME}" -p $${EGISDBPORT} -d "$${EGISDBNAME}" -c "DROP SCHEMA IF EXISTS reference CASCADE;"

echo "Setting up fim schema in the EGIS DB..."
aws s3 cp "s3://$${DEPLOYMENT_BUCKET}/viz/db_pipeline/db_dumps/egisDB_reference.dump" "$${HOME}/egisDB_reference.dump"
pg_restore -h "$${EGISDBHOST}" -p $${EGISDBPORT} -d "$${EGISDBNAME}" -U $${EGISDBUSERNAME} -j 4 -v "$${HOME}/egisDB_reference.dump"
rm "$${HOME}/egisDB_reference.dump"

