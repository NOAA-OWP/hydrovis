#!/bin/bash

echo "---- SETTING UP INGEST DB ----"

FORECASTDB="${FORECASTDB}"
LOCATIONDB="${LOCATIONDB}"
DBHOST="${DBHOST}"
DBPORT=${DBPORT}
DBUSERNAME="${DBUSERNAME}"
DBPASSWORD="${DBPASSWORD}"
DEPLOYMENT_BUCKET="${DEPLOYMENT_BUCKET}"
INGESTDBUSERS="${INGESTDBUSERS}"
LOCATIONDBUSERS="${LOCATIONDBUSERS}"

### install postgresql ###
sudo yum install -y postgresql12

### Constants ###
HOME="/home/ec2-user"
PGPASS="$${HOME}/.pgpass"
HML_S3_PREFIX="ingest/database"
POSTGIS_SCRIPT="postgis_setup.sql"
USERS_SCRIPT="ingest_users.sql"
BASE_SCRIPT="$${FORECASTDB}_base.sql.gz"
LOCATION_S3_PREFIX="location/database"
LOCATION_DUMP="wrds_location3.dump"
DOWNLOAD_DIRECTORY="$${HOME}/postgres_data"
POSTGIS_FILE="$${DOWNLOAD_DIRECTORY}/$${POSTGIS_SCRIPT}"
BASE_FILE="$${DOWNLOAD_DIRECTORY}/$${BASE_SCRIPT}"
USERS_FILE="/deploy_files/$${USERS_SCRIPT}"
LOCATION_FILE="$${DOWNLOAD_DIRECTORY}/$${LOCATION_DUMP}"
DROP_DATABASE=0
REMOVE_BASE_FILE=0
REMOVE_USERS_FILE=0
REMOVE_DIRECTORY=0

export PGPASSWORD=$${DBPASSWORD}

### Create/validate pgpass file ###
function create_pgpass()
{
  local FOUND=0
  local DBPASSLINE="$${DBHOST}:*:*:$${DBUSERNAME}:$${DBPASSWORD}"
  ### Check to see if file is present, and if so, validate it ###
  if [ -f "$${DBPASS}" ]
  then
    while IFS= read -r LINE
    do
      if [ "$${LINE}" = "$${DBPASSLINE}" ]
      then
        FOUND=1
        break 
      fi
    done < "$${DBPASS}"
    if [ $${FOUND} -eq 0 ]
    then
      echo "Appending line to $${DBPASS}"
      echo "$${DBPASSLINE}" >> "$${DBPASS}"
    else
      echo "Matching entry found in $${DBPASS}. No need to modify."
    fi
  else
    echo "Creating new $${DBPASS}..."
    echo "$${DBPASSLINE}" > "$${DBPASS}"
  fi

  chmod 600 "$${DBPASS}"
}

# Create PGPASS
create_pgpass

# Download database contents
echo "Downloading s3://$${DEPLOYMENT_BUCKET}/$${HML_S3_PREFIX}/$${POSTGIS_SCRIPT}..."
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${HML_S3_PREFIX}/$${POSTGIS_SCRIPT} $${DOWNLOAD_DIRECTORY}/
REMOVE_BASE_FILE=1

echo "Downloading s3://$${DEPLOYMENT_BUCKET}/$${HML_S3_PREFIX}/$${BASE_SCRIPT}..."
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${HML_S3_PREFIX}/$${BASE_SCRIPT} $${DOWNLOAD_DIRECTORY}/
REMOVE_BASE_FILE=1

echo "Downloading s3://$${DEPLOYMENT_BUCKET}/$${LOCATION_S3_PREFIX}/$${LOCATION_DUMP}..."
aws s3 cp s3://$${DEPLOYMENT_BUCKET}/$${LOCATION_S3_PREFIX}/$${LOCATION_DUMP} $${DOWNLOAD_DIRECTORY}/
REMOVE_BASE_FILE=1

REMOVE_USERS_FILE=1

# Uncompress
gzip -d "$${BASE_FILE}"
BASE_FILE="$${BASE_FILE/.gz}"

# Setting up DB
echo "Setting up postgis.."
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${FORECASTDB}" -f "$${POSTGIS_FILE}"

# Update users
echo "Creating users..."
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT}  -d "$${FORECASTDB}" -f "$${USERS_FILE}"

# Updating permissions
echo "Granting database level permissions..."
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT}  -d "$${FORECASTDB}" \
    -tAc "REVOKE CONNECT ON DATABASE $${FORECASTDB} FROM PUBLIC;
            GRANT CONNECT ON DATABASE $${FORECASTDB} to $${INGESTDBUSERS};
            COMMENT ON DATABASE $${FORECASTDB} IS 
            'database for storing river forecasts';"

# Create table schemas for HML Ingest
echo "Setting up HML ingest on $${PGHOST}..."
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${FORECASTDB}" -f "$${BASE_FILE}"

# Dump WRDS Location
echo "Setting up WRDS Location on $${PGHOST}..."
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -d "$${FORECASTDB}" -c "\c" -c "create database $${LOCATIONDB};"
pg_restore -h "$${DBHOST}" -p $${DBPORT} -d "$${LOCATIONDB}" -U $${DBUSERNAME} -v $${LOCATION_FILE}

# Updating permissions
echo "Granting database level permissions..."
psql -h "$${DBHOST}" -U "$${DBUSERNAME}" -p $${DBPORT} -d "$${LOCATIONDB}" \
    -tAc "REVOKE CONNECT ON DATABASE $${LOCATIONDB} FROM PUBLIC;
            GRANT CONNECT ON DATABASE $${LOCATIONDB} to $${LOCATIONDBUSERS};
            COMMENT ON DATABASE $${LOCATIONDB} IS 
            'database for storing location metadata';"

DROP_DATABASE=0



