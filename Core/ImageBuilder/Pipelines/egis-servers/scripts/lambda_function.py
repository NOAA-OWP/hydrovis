import json
import boto3
import logging
import os
from botocore.exceptions import ClientError

logger = logging.getLogger()
logger.setLevel(logging.INFO)

ssm_prefix = os.getenv("ssm_prefix")
ssm_parameter_name = f"{ssm_prefix}/ec2-imagebuilder"
session = boto3.session.Session()


def lambda_handler(event, context):
	logger.info("Printing event: {}".format(event))
	process_sns_event(event)
	return None


def process_sns_event(event):
	for record in event["Records"]:
		event_message = record["Sns"]["Message"]
		logger.info(f"Event message: {event_message}")

		# convert the event message to json
		message_json = json.loads(event_message)

		# obtain the image state
		image_state = message_json["state"]["status"]

		# update the SSM parameter if the image state is available
		if image_state == "AVAILABLE":
			logger.info("Image is available")

			recipe_name = message_json["name"]
			egis_server_type = recipe_name.replace("-recipe", "")
			logger.info(f"Updating AMIs for build: {egis_server_type}")

			for ami in message_json["outputResources"]["amis"]:
				# obtain ami id
				logger.info("AMI ID: {}".format(ami["image"]))
				logger.info("Account ID: {0}/{1}".format(ami["accountId"],ami["region"]))

				# init old ami value
				oldamiidvalue = ""

				# Initialize the AWS clients to update SSM Parameter
				ssm_client = session.client(
					service_name="ssm",
					region_name=ami["region"],
				)
				sts_client = session.client(
					service_name="sts",
				)

				# Define the parameters for assuming the role in the target account
				role_to_assume_arn = f"arn:aws:iam::{ami['accountId']}:role/AutomationExecutionHandlerFunctionRole"
				role_session_name = "lambda_ami_distribution_function"

				# Assume the role in the target account
				assumed_role = sts_client.assume_role(
						RoleArn=role_to_assume_arn,
						RoleSessionName=role_session_name
				)

				# Extract temporary credentials from the assumed role response
				assumed_credentials = assumed_role["Credentials"]

				# Initialize an SSM client using the assumed credentials
				assumed_ssm_client = boto3.client(
						"ssm",
						aws_access_key_id=assumed_credentials['AccessKeyId'],
						aws_secret_access_key=assumed_credentials['SecretAccessKey'],
						aws_session_token=assumed_credentials['SessionToken']
				)
    
		    # Now you can use the assumed_ssm_client to update SSM parameters in the target account
				try:
					oldamiid = assumed_ssm_client.get_parameter(
						Name=f"{ssm_parameter_name}/{egis_server_type}/CurrentAMIId",
						WithDecryption=True,
					)
					oldamiidvalue = oldamiid["Parameter"]["Value"]
					oldtagsresponse = assumed_ssm_client.list_tags_for_resource(
						ResourceType="Parameter",
						ResourceId=f"{ssm_parameter_name}/{egis_server_type}/CurrentAMIId",
					)
					oldtags = oldtagsresponse.get("TagList", [])

				except ClientError as e:
					if e.response["Error"]["Code"] == "ParameterNotFound":
						logger.info(
							f"{ssm_parameter_name}/{egis_server_type}/CurrentAMIId not found"
						)
					else:
						logger.info(
							f"Error retrieving parameter {ssm_parameter_name}/{egis_server_type}/CurrentAMIId: {e}"
						)

				if oldamiidvalue != "":
					# Compare old and new values
					if oldamiidvalue == ami["image"]:
						logger.info(
							f"CurrentAMIId is already stored. No update needed."
						)
						continue

					# Update the "PreviousAMIId" parameter with the current value
					response = assumed_ssm_client.put_parameter(
						Name=f"{ssm_parameter_name}/{egis_server_type}/PreviousAMIId",
						Description="Previous AMI ID",
						Value=oldamiidvalue,
						Type="String",
						Overwrite=True,
						Tier="Standard",
					)
					for tag in oldtags:
						assumed_ssm_client.add_tags_to_resource(
							ResourceType="Parameter",
							ResourceId=f"{ssm_parameter_name}/{egis_server_type}/PreviousAMIId",
							Tags=[{"Key": tag["Key"], "Value": tag["Value"]}],
						)
					logger.info("SSM Updated Previous AMI ID: {}".format(response))

				# Update the "CurrentAMIId" parameter with the new value
				response = assumed_ssm_client.put_parameter(
					Name=f"{ssm_parameter_name}/{egis_server_type}/CurrentAMIId",
					Description="Latest AMI ID",
					Value=ami["image"],
					Type="String",
					Overwrite=True,
					Tier="Standard",
				)
				logger.info("SSM Updated Current AMI ID: {}".format(response))

				# add tags to the SSM parameters
				assumed_ssm_client.add_tags_to_resource(
					ResourceType="Parameter",
					ResourceId=f"{ssm_parameter_name}/{egis_server_type}/CurrentAMIId",
					Tags=[
						{"Key": "Source", "Value": "EC2 Image Builder"},
						{"Key": "AMI_REGION", "Value": ami["region"]},
						{"Key": "AMI_ID", "Value": ami["image"]},
						{"Key": "AMI_NAME", "Value": ami["name"]},
						{"Key": "RECIPE_NAME", "Value": recipe_name},
						{
							"Key": "SOURCE_PIPELINE_ARN",
							"Value": message_json["sourcePipelineArn"],
						},
					],
				)
		# end of Lambda function
		return None
