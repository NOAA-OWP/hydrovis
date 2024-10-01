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
                logger.info(
                    "Account ID: {0}/{1}".format(ami["accountId"], ami["region"])
                )

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
                    RoleArn=role_to_assume_arn, RoleSessionName=role_session_name
                )

                # Extract temporary credentials from the assumed role response
                assumed_credentials = assumed_role["Credentials"]

                # Initialize an SSM client using the assumed credentials
                assumed_ssm_client = boto3.client(
                    "ssm",
                    region_name=ami["region"],
                    aws_access_key_id=assumed_credentials["AccessKeyId"],
                    aws_secret_access_key=assumed_credentials["SecretAccessKey"],
                    aws_session_token=assumed_credentials["SessionToken"],
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


# If running the script directly (not as a Lambda function)
if __name__ == "__main__":
    event = {
        "Records": [
            {
                "EventSource": "aws:sns",
                "EventVersion": "1.0",
                "EventSubscriptionArn": "arn:aws:sns:us-east-1:526904826677:esri-image-builder-sns-topic:9bff6af0-a640-49b7-bb19-21e17e1237ff",
                "Sns": {
                    "Type": "Notification",
                    "MessageId": "b14e8a29-01c3-59ac-b216-d56135ed9943",
                    "TopicArn": "arn:aws:sns:us-east-1:526904826677:esri-image-builder-sns-topic",
                    "Subject": None,
                    "Message": '{\n  "semver": 1237940046202909303613947905,\n  "platform": "Windows",\n  "workflows": [\n    {\n      "workflowArn": "arn:aws:imagebuilder:us-east-1:627945338248:workflow/build/build-image/1.0.1/1"\n    },\n    {\n      "workflowArn": "arn:aws:imagebuilder:us-east-1:627945338248:workflow/test/test-image/1.0.1/1"\n    }\n  ],\n  "tags": {\n    "resourceArn": "arn:aws:imagebuilder:us-east-1:526904826677:image/arcgisserver-11-3-recipe/1.6.1/1",\n    "internalId": "14e01eb7-bc04-4460-90b6-47c2c0277928"\n  },\n  "version": "1.6.1",\n  "executionRole": "arn:aws:iam::526904826677:role/aws-service-role/imagebuilder.amazonaws.com/AWSServiceRoleForImageBuilder",\n  "arn": "arn:aws:imagebuilder:us-east-1:526904826677:image/arcgisserver-11-3-recipe/1.6.1/1",\n  "buildVersion": 1,\n  "name": "arcgisserver-11-3-recipe",\n  "outputResources": {\n    "amis": [\n      {\n        "region": "us-east-1",\n        "accountId": "526904826677",\n        "image": "ami-0260900d063de06d6",\n        "name": "arcgisserver-11-3-2024-08-27T18-43-22.629Z"\n      },\n      {\n        "region": "us-east-1",\n        "accountId": "799732994462",\n        "image": "ami-069fcf398dbd7327e",\n        "name": "arcgisserver-11-3-2024-08-27T18-43-22.629Z"\n      },\n      {\n        "region": "us-east-1",\n        "accountId": "734632823696",\n        "image": "ami-03911fee9a0710254",\n        "name": "arcgisserver-11-3-2024-08-27T18-43-22.629Z"\n      },\n      {\n        "region": "us-east-2",\n        "accountId": "799732994462",\n        "image": "ami-0bb754bc522f77b2a",\n        "name": "arcgisserver-11-3-2024-08-27T18-43-22.629Z"\n      },\n      {\n        "region": "us-east-2",\n        "accountId": "734632823696",\n        "image": "ami-0fa08dd2911e3cb1d",\n        "name": "arcgisserver-11-3-2024-08-27T18-43-22.629Z"\n      }\n    ]\n  },\n  "sourcePipelineArn": "arn:aws:imagebuilder:us-east-1:526904826677:image-pipeline/arcgisserver-11-3",\n  "infrastructureConfiguration": {\n    "logging": {\n      "s3Logs": {\n        "s3BucketName": "hydrovis-11-3-deployment",\n        "s3KeyPrefix": "imagebuilder/logs"\n      }\n    },\n    "keyPair": "hv-ti-ec2-key-pair-us-east-1",\n    "instanceProfileName": "svc-EC2-ImageSTIG-builder",\n    "description": "Infrastructure to build ArcGIS images",\n    "accountId": "526904826677",\n    "resourceTags": {\n      "Service": "Esri Professional Services",\n      "CodeDeployContact": "drix.tabligan@noaa.gov",\n      "CodeDeployService": "Gama1 HydroVIS Support Team",\n      "Contact": "robert.van@noaa.gov"\n    },\n    "dateUpdated": "Aug 27, 2024 3:49:02 PM",\n    "terminateInstanceOnFailure": true,\n    "dateCreated": "Nov 17, 2023 3:20:23 PM",\n    "subnetId": "subnet-0f97f79b11479c54d",\n    "securityGroupIds": [\n      "sg-0ba2e3e187b78f05c"\n    ],\n    "name": "arcgis_build_infrastructure",\n    "snsTopicArn": "arn:aws:sns:us-east-1:526904826677:esri-image-builder-sns-topic",\n    "instanceTypes": [\n      "m5.xlarge"\n    ],\n    "arn": "arn:aws:imagebuilder:us-east-1:526904826677:infrastructure-configuration/arcgis-build-infrastructure",\n    "tags": {\n      "resourceArn": "arn:aws:imagebuilder:us-east-1:526904826677:infrastructure-configuration/arcgis-build-infrastructure",\n      "internalId": "56875e0f-91e7-4051-abc3-05c82b3b49ae"\n    }\n  },\n  "state": {\n    "status": "AVAILABLE"\n  },\n  "type": "AMI",\n  "enhancedImageMetadataEnabled": true,\n  "osVersion": "Microsoft Windows Server 2022",\n  "accountId": "526904826677",\n  "distributionConfiguration": {\n    "accountId": "526904826677",\n    "dateCreated": "Aug 27, 2024 6:42:36 PM",\n    "arn": "arn:aws:imagebuilder:us-east-1:526904826677:distribution-configuration/arcgisserver-11-3-distribution",\n    "tags": {\n      "resourceArn": "arn:aws:imagebuilder:us-east-1:526904826677:distribution-configuration/arcgisserver-11-3-distribution",\n      "internalId": "ca63a231-b7bb-47ab-b404-797b7738bbca"\n    },\n    "distributions": [\n      {\n        "amiDistributionConfiguration": {\n          "amiTags": {\n            "CreatedBy": "Terraform",\n            "owp_group": "vpp",\n            "Service": "Esri Professional Services",\n            "noaa:programoffice": "owp",\n            "CodeDeployContact": "drix.tabligan@noaa.gov",\n            "CodeDeployService": "Gama1 HydroVIS Support Team",\n            "Contact": "robert.van@noaa.gov",\n            "Name": "arcgisserver-11-3-distribution",\n            "hydrovis-region": "us-east-1",\n            "noaa:fismaid": "noaa8501",\n            "noaa:project": "hydrovis",\n            "hydrovis-env": "ti",\n            "noaa:projectid": "526904826677",\n            "TaskOrderID": "1305L420QNWWJ0057",\n            "noaa:lineoffice": "nws"\n          },\n          "targetAccountIds": [\n            "799732994462",\n            "734632823696"\n          ],\n          "name": "arcgisserver-11-3-2024-08-27T18-43-22.629Z"\n        },\n        "region": "us-east-1"\n      },\n      {\n        "amiDistributionConfiguration": {\n          "amiTags": {\n            "CreatedBy": "Terraform",\n            "owp_group": "vpp",\n            "Service": "Esri Professional Services",\n            "noaa:programoffice": "owp",\n            "CodeDeployContact": "drix.tabligan@noaa.gov",\n            "CodeDeployService": "Gama1 HydroVIS Support Team",\n            "Contact": "robert.van@noaa.gov",\n            "Name": "arcgisserver-11-3-distribution",\n            "hydrovis-region": "us-east-1",\n            "noaa:fismaid": "noaa8501",\n            "noaa:project": "hydrovis",\n            "hydrovis-env": "ti",\n            "noaa:projectid": "526904826677",\n            "TaskOrderID": "1305L420QNWWJ0057",\n            "noaa:lineoffice": "nws"\n          },\n          "targetAccountIds": [\n            "799732994462",\n            "734632823696"\n          ],\n          "name": "arcgisserver-11-3-2024-08-27T18-43-22.629Z"\n        },\n        "region": "us-east-2"\n      }\n    ],\n    "name": "arcgisserver-11-3-distribution"\n  },\n  "versionlessArn": "arn:aws:imagebuilder:us-east-1:526904826677:image/arcgisserver-11-3-recipe",\n  "dateCreated": "Aug 27, 2024 6:43:22 PM",\n  "buildType": "USER_INITIATED",\n  "imageRecipe": {\n    "components": [\n      {\n        "componentArn": "arn:aws:imagebuilder:us-east-1:627945338248:component/amazon-cloudwatch-agent-windows/1.0.0/1"\n      },\n      {\n        "componentArn": "arn:aws:imagebuilder:us-east-1:526904826677:component/arcgisenteprise-esri-cinc-bootstrap/1.6.1/1",\n        "parameters": [\n          {\n            "value": [\n              "s3://hydrovis-11-3-deployment/software/v11-3"\n            ],\n            "name": "S3Source"\n          },\n          {\n            "value": [\n              "c:/software"\n            ],\n            "name": "WorkingFolder"\n          }\n        ]\n      },\n      {\n        "componentArn": "arn:aws:imagebuilder:us-east-1:526904826677:component/arcgisenteprise-esri-run-cinc-client/1.6.1/1",\n        "parameters": [\n          {\n            "value": [\n              "c:/software"\n            ],\n            "name": "WorkingFolder"\n          },\n          {\n            "value": [\n              "install-arcgis-server.json"\n            ],\n            "name": "CincConfig"\n          }\n        ]\n      },\n      {\n        "componentArn": "arn:aws:imagebuilder:us-east-1:526904826677:component/arcgisenteprise-esri-patching/1.6.1/1",\n        "parameters": [\n          {\n            "value": [\n              "c:/software"\n            ],\n            "name": "WorkingFolder"\n          }\n        ]\n      },\n      {\n        "componentArn": "arn:aws:imagebuilder:us-east-1:627945338248:component/stig-build-windows-high/2022.4.0/1"\n      },\n      {\n        "componentArn": "arn:aws:imagebuilder:us-east-1:526904826677:component/server-additional-installs/1.6.1/1"\n      },\n      {\n        "componentArn": "arn:aws:imagebuilder:us-east-1:627945338248:component/reboot-windows/1.0.1/1"\n      }\n    ],\n    "parentImage": "arn:aws:imagebuilder:us-east-1:627945338248:image/windows-server-2022-english-full-base-x86/2024.8.14/1",\n    "accountId": "526904826677",\n    "platform": "Windows",\n    "version": "1.6.1",\n    "blockDeviceMappings": [\n      {\n        "deviceName": "/dev/sda1",\n        "ebs": {\n          "volumeSize": 200,\n          "deleteOnTermination": true,\n          "volumeType": "gp3"\n        }\n      }\n    ],\n    "dateCreated": "Aug 27, 2024 6:42:37 PM",\n    "arn": "arn:aws:imagebuilder:us-east-1:526904826677:image-recipe/arcgisserver-11-3-recipe/1.6.1",\n    "tags": {\n      "resourceArn": "arn:aws:imagebuilder:us-east-1:526904826677:image-recipe/arcgisserver-11-3-recipe/1.6.1",\n      "internalId": "a8993e7b-70e2-4b6b-8477-c0feeb52ca5c"\n    },\n    "name": "arcgisserver-11-3-recipe"\n  },\n  "imageTestsConfigurationDocument": {\n    "timeoutMinutes": 1440,\n    "imageTestsEnabled": true\n  },\n  "buildExecutionId": "2adda735-18d6-4e62-8a67-743eb3fd92d9",\n  "testExecutionId": "00f021e5-8970-4838-995a-0306812ff730",\n  "distributionJobId": "d9984371-f2a2-49b8-b51c-8bfa86aed50e",\n  "integrationJobId": "47418a91-7009-4be1-8045-bab0f1b92255"\n}',
                    "Timestamp": "2024-08-27T20:07:10.268Z",
                    "SignatureVersion": "1",
                    "Signature": "nxLvmP5uNp87GXN2J4CenRv5gkK5i02wl4qSOGTAidZYCNemVSRwVtklTXL2CSuBY1Gn/HknyJXaUd1OZItp4uLtvkgoQLuO/JWQ08rJnrbV3cRiquSPfQYZg1DDqsLE8wt7IhqHDn/Hpr5bIc6JP1llm6ur6MqVsO+GPGUz21sNUkjR7ZK9HpVEfVlOAlBFRQJrgZAGzSageBu1GvRfeDLaUeK7bjCrJreev3muxB0QqmcUfChtqsK7WlGpp8yqxa1dS/2PUO8PZQB+tPe6Vk3z15ft8jJdLciwi03zS3LLg9Uow3l14pVS6fRR3uUfEGrAqhi4sZCWmkAqtfbJmQ==",
                    "SigningCertUrl": "https://sns.us-east-1.amazonaws.com/SimpleNotificationService-60eadc530605d63b8e62a523676ef735.pem",
                    "UnsubscribeUrl": "https://sns.us-east-1.amazonaws.com/?Action=Unsubscribe&SubscriptionArn=arn:aws:sns:us-east-1:526904826677:esri-image-builder-sns-topic:9bff6af0-a640-49b7-bb19-21e17e1237ff",
                    "MessageAttributes": {},
                },
            }
        ]
    }

    lambda_handler(event, None)
