import boto3
import os
import psycopg2



def get_db_credentials(db_type):
    """
    This function pulls database credentials from environment variables.
    It first checks for a password in an environment variable.
    If that doesn't exist, it tries looking or a secret name to query for
    the password using the get_secret_password function.

    Returns:
        db_host (str): The host address of the PostgreSQL database.
        db_name (str): The target database name.
        db_user (str): The database user with write access to authenticate with.
        db_password (str): The password for the db_user.

    """
    db_type = db_type.upper()

    db_host = os.environ[f'{db_type}_DB_HOST']
    db_name = os.environ[f'{db_type}_DB_DATABASE']
    db_user = os.environ[f'{db_type}_DB_USERNAME']
    try:
        db_password = os.getenv(f'{db_type}_DB_PASSWORD')
    except Exception:
        try:
            db_password = get_secret_password(os.getenv(f'{db_type}_RDS_SECRET_NAME'), 'us-east-1', 'password')
        except Exception as e:
            print(f"Couldn't get db password from environment variable or secret name. ({e})")

    return db_host, db_name, db_user, db_password

def get_db_engine(db_type):
    from sqlalchemy import create_engine

    db_host, db_name, db_user, db_password = get_db_credentials(db_type)
    db_engine = create_engine(f'postgresql://{db_user}:{db_password}@{db_host}/{db_name}')

    return db_engine

def get_db_connection(db_type, asynchronous=False):
    db_host, db_name, db_user, db_password = get_db_credentials(db_type)
    connection = psycopg2.connect(
        f"host={db_host} dbname={db_name} user={db_user} password={db_password}", async_=asynchronous
    )

    return connection

def sql_to_dataframe(sql, db_type="viz", return_geodataframe=False):
    if sql.endswith(".sql"):
        sql = open(sql, 'r').read()

    db_engine = get_db_engine(db_type)
    if not return_geodataframe:
        import pandas as pd
        df = pd.read_sql(sql, db_engine)
    else:
        import geopandas as gdp
        df = gdp.GeoDataFrame.from_postgis(sql, db_engine)

    db_engine.dispose()
    return df


def execute_sql(sql, db_type="viz"):
    db_connection = get_db_connection(db_type)

    try:
        cur = db_connection.cursor()
        cur.execute(sql)
        db_connection.commit()
    except Exception as e:
        raise e
    finally:
        db_connection.close()

def get_secret_password(secret_name, region_name, key):
    """
        Gets a password from a sercret stored in AWS secret manager.

        Args:
            secret_name(str): The name of the secret
            region_name(str): The name of the region

        Returns:
            password(str): The text of the password
    """

    # Create a Secrets Manager client
    session = boto3.session.Session()
    client = session.client(
        service_name='secretsmanager',
        region_name=region_name
    )

    # In this sample we only handle the specific exceptions for the 'GetSecretValue' API.
    # See https://docs.aws.amazon.com/secretsmanager/latest/apireference/API_GetSecretValue.html
    # We rethrow the exception by default.

    try:
        get_secret_value_response = client.get_secret_value(
            SecretId=secret_name
        )
    except ClientError as e:
        if e.response['Error']['Code'] == 'DecryptionFailureException':
            # Secrets Manager can't decrypt the protected secret text using the provided KMS key.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InternalServiceErrorException':
            # An error occurred on the server side.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidParameterException':
            # You provided an invalid value for a parameter.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'InvalidRequestException':
            # You provided a parameter value that is not valid for the current state of the resource.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        elif e.response['Error']['Code'] == 'ResourceNotFoundException':
            # We can't find the resource that you asked for.
            # Deal with the exception here, and/or rethrow at your discretion.
            raise e
        else:
            print(e)
            raise e
    else:
        # Decrypts secret using the associated KMS CMK.
        # Depending on whether the secret is a string or binary, one of these fields will be populated.
        if 'SecretString' in get_secret_value_response:
            secret = get_secret_value_response['SecretString']
            j = json.loads(secret)
            password = j[key]
        else:
            decoded_binary_secret = base64.b64decode(get_secret_value_response['SecretBinary'])
            print("password binary:" + decoded_binary_secret)
            password = decoded_binary_secret.password

        return password
