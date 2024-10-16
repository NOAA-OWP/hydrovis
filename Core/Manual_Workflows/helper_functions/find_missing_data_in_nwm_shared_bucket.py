import datetime as dt
import boto3
import botocore

S3 = boto3.resource('s3')
STEP = dt.timedelta(hours=1)
BUCKET = 'nws-shared-data-226711853580-us-east-1'
CONFIGURATIONS = ['analysis_assim']
VARIABLES = {
    'analysis_assim': ['channel_rt', 'forcing']
}
DOMAINS = {
    'analysis_assim': ['conus', 'puertorico', 'alaska', 'hawaii']
}

KEY_TEMPLATE = 'common/data/model/com/nwm/prod/nwm.{YYMMDD}/{full_configuration}/nwm.t{HH}z.{configuration}.{variable}.tm00.{domain}.nc'

def main(START, END, print_progress=False):
    missing_files = []
    iter_dt = START
    while iter_dt < END:
        for configuration in CONFIGURATIONS:
            for variable in VARIABLES[configuration]:
                for domain in DOMAINS[configuration]:
                    if domain == 'hawaii' and variable == 'channel_rt': break
                    full_configuration = configuration
                    if variable == 'forcing':
                        full_configuration = f'forcing_{configuration}'
                    if domain != 'conus':
                        full_configuration = f'{full_configuration}_{domain}'
                        key = KEY_TEMPLATE.format(
                            YYMMDD=iter_dt.strftime('%Y%m%d'),
                            full_configuration=full_configuration,
                            HH=iter_dt.strftime('%H'),
                            configuration=configuration,
                            variable=variable,
                            domain=domain
                        )
                        if print_progress:
                            print(f"Checking for {key}...")
                        try:
                            S3.Object(BUCKET, key).load()
                        except botocore.exceptions.ClientError as e:
                            if e.response['Error']['Code'] == "404":
                                if print_progress:
                                    print("... UH OH! 404!")
                                missing_files.append(key)
                            else:
                                raise
                        else:
                            # The file exists!
                            pass
        iter_dt += STEP

    return missing_files