### install postgresql ###
sudo yum install -y postgresql12

### Constants ###
HOME="/home/ec2-user"
PGPASS="${HOME}/.pgpass"
HML_S3_PREFIX="ingest/database"
POSTGIS_SCRIPT="postgis_setup.sql"
USERS_SCRIPT="db_users.sql"
BASE_SCRIPT="${FORECASTDB}_base.sql.gz"
LOCATION_S3_PREFIX="location/database"
LOCATION_DUMP="wrds_location3.dump"
DOWNLOAD_DIRECTORY="${HOME}/postgres_data"
POSTGIS_FILE="${DOWNLOAD_DIRECTORY}/${POSTGIS_SCRIPT}"
BASE_FILE="${DOWNLOAD_DIRECTORY}/${BASE_SCRIPT}"
USERS_FILE="/deploy_files/${USERS_SCRIPT}"
LOCATION_FILE="${DOWNLOAD_DIRECTORY}/${LOCATION_DUMP}"
DROP_DATABASE=0
REMOVE_BASE_FILE=0
REMOVE_USERS_FILE=0
REMOVE_DIRECTORY=0

export PGPASSWORD=${PGPASSWORD}

### Create/validate pgpass file ###
function create_pgpass()
{
  local FOUND=0
  local PGPASSLINE="${PGHOST}:*:*:${PGUSERNAME}:${PGPASSWORD}"
  ### Check to see if file is present, and if so, validate it ###
  if [ -f "${PGPASS}" ]
  then
    while IFS= read -r LINE
    do
      if [ "${LINE}" = "${PGPASSLINE}" ]
      then
        FOUND=1
        break 
      fi
    done < "${PGPASS}"
    if [ ${FOUND} -eq 0 ]
    then
      echo "Appending line to ${PGPASS}"
      echo "${PGPASSLINE}" >> "${PGPASS}"
    else
      echo "Matching entry found in ${PGPASS}. No need to modify."
    fi
  else
    echo "Creating new ${PGPASS}..."
    echo "${PGPASSLINE}" > "${PGPASS}"
  fi

  chmod 600 "${PGPASS}"
}

# Create PGPASS
create_pgpass

# Download database contents
echo "Downloading s3://${DEPLOYMENT_BUCKET}/${HML_S3_PREFIX}/${POSTGIS_SCRIPT}..."
aws s3 cp s3://${DEPLOYMENT_BUCKET}/${HML_S3_PREFIX}/${POSTGIS_SCRIPT} ${DOWNLOAD_DIRECTORY}/
REMOVE_BASE_FILE=1

echo "Downloading s3://${DEPLOYMENT_BUCKET}/${HML_S3_PREFIX}/${BASE_SCRIPT}..."
aws s3 cp s3://${DEPLOYMENT_BUCKET}/${HML_S3_PREFIX}/${BASE_SCRIPT} ${DOWNLOAD_DIRECTORY}/
REMOVE_BASE_FILE=1

echo "Downloading s3://${DEPLOYMENT_BUCKET}/${LOCATION_S3_PREFIX}/${LOCATION_DUMP}..."
aws s3 cp s3://${DEPLOYMENT_BUCKET}/${LOCATION_S3_PREFIX}/${LOCATION_DUMP} ${DOWNLOAD_DIRECTORY}/
REMOVE_BASE_FILE=1

REMOVE_USERS_FILE=1

# Uncompress
gzip -d "${BASE_FILE}"
BASE_FILE="${BASE_FILE/.gz}"

# Setting up DB
echo "Setting up postgis.."
psql -h "${PGHOST}" -U "${PGUSERNAME}" -p ${PGPORT} -d "${FORECASTDB}" -f "${POSTGIS_FILE}"

# Update users
echo "Creating users..."
psql -h "${PGHOST}" -U "${PGUSERNAME}" -p ${PGPORT} -d "${FORECASTDB}" -f "${USERS_FILE}"

# Updating permissions
echo "Granting database level permissions..."
psql -h "${PGHOST}" -U "${PGUSERNAME}" -p ${PGPORT} -d "${FORECASTDB}" \
    -tAc "REVOKE CONNECT ON DATABASE ${FORECASTDB} FROM PUBLIC;
            GRANT CONNECT ON DATABASE ${FORECASTDB} to ${RFCDBUSERS};
            COMMENT ON DATABASE ${FORECASTDB} IS 
            'database for storing river forecasts';"

# Create table schemas for HML Ingest
echo "Setting up HML ingest on ${PGHOST}..."
psql -h "${PGHOST}" -U "${PGUSERNAME}" -p ${PGPORT} -d "${FORECASTDB}" -f "${BASE_FILE}"

# Dump WRDS Location
echo "Setting up WRDS Location on ${PGHOST}..."
psql -h "${PGHOST}" -U "${PGUSERNAME}" -d "${FORECASTDB}" -c "\c" -c "create database ${LOCATIONDB};"
pg_restore -h "${PGHOST}" -p ${PGPORT} -d "${LOCATIONDB}" -U ${PGUSERNAME} -v ${LOCATION_FILE}

# Updating permissions
echo "Granting database level permissions..."
psql -h "${PGHOST}" -U "${PGUSERNAME}" -p ${PGPORT} -d "${LOCATIONDB}" \
    -tAc "REVOKE CONNECT ON DATABASE ${LOCATIONDB} FROM PUBLIC;
            GRANT CONNECT ON DATABASE ${LOCATIONDB} to ${LOCATIONDBUSERS};
            COMMENT ON DATABASE ${LOCATIONDB} IS 
            'database for storing location metadata';"

DROP_DATABASE=0

