import boto3
from datetime import datetime
import json
from aws_loosa.ec2 import consts
import os

def kickoff_viz_lambdas():
    client = boto3.client('lambda')
    max_flows_lambda = f"viz_max_flows_{consts.hydrovis_env_map[os.environ['VIZ_ENVIRONMENT']]}"
    ingest_lambda = f"viz_db_ingest_{consts.hydrovis_env_map[os.environ['VIZ_ENVIRONMENT']]}"
    postprocess_lambda = f"viz_db_postprocess_{consts.hydrovis_env_map[os.environ['VIZ_ENVIRONMENT']]}"

    print("Invoking max flows function for AnA 14 day")
    current_datetime = datetime.utcnow()
    current_date = current_datetime.strftime("%Y%m%d")
    latest_0Z_ana_file = f"common/data/model/com/nwm/prod/nwm.{current_date}/analysis_assim/nwm.t00z.analysis_assim.channel_rt.tm00.conus.nc"  # noqa: E501
    max_flows_payload = {"data_key": latest_0Z_ana_file, "data_bucket": os.environ['NWM_DATA_BUCKET']}

    client.invoke(
        FunctionName=max_flows_lambda,
        InvocationType='Event',
        Payload=bytes(json.dumps(max_flows_payload), "utf-8")
    )

    nwm_configurations = [
        "analysis_assim", "analysis_assim_hawaii", "analysis_assim_puertorico", "short_range", "short_range_hawaii",
        "short_range_puertorico", "medium_range_mem1"
    ]

    for configuration in nwm_configurations:
        print(f"Invoking db_ingest function for {configuration}")
        ingest_payload = {"configuration": configuration, "bucket": os.environ['NWM_DATA_BUCKET']}
        client.invoke(
            FunctionName=ingest_lambda,
            InvocationType='Event',
            Payload=bytes(json.dumps(ingest_payload), "utf-8")
        )


    print(f"Invoking db_ingest function for replace_route")
    ingest_payload = {"configuration": "replace_route", "bucket": os.environ['RNR_MAX_FLOWS_DATA_BUCKET']}
    client.invoke(
        FunctionName=ingest_lambda,
        InvocationType='Event',
        Payload=bytes(json.dumps(ingest_payload), "utf-8")
    )

    print(f"Invoking db_postprocess function for reference services")
    postprocess_payload = {
        "configuration": "reference", "reference_time": current_datetime.strftime("%Y-%m-%d %H:%M:%S")
    }
    client.invoke(
        FunctionName=postprocess_lambda,
        InvocationType='Event',
        Payload=bytes(json.dumps(postprocess_payload), "utf-8")
    )


if __name__ == '__main__':

    kickoff_viz_lambdas()