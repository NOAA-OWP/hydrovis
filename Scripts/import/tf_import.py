import boto3
import os
import json
import subprocess
import inspect

# Region to import from 
region = ""

# The type of AWS resource that you're wanting to import into Terraform
resource_type = ""

# VPC that you want to create the config for (if applicable)
vpc_id = ''

# Set aws profile that you want to import from
aws_profile = ''


boto3.setup_default_session(profile_name=aws_profile)

#############################################################
########## EDIT CODE HERE FOR NEW RESOURCE TYPES ############
#############################################################
# A resource generator function and set of desired_attributes need to be defined here for the resource you want to import

######################################################################################
# TIPS FOR USING THE BOTO3 PACKAGE IN YOUR RESOURCE GENERATOR FUNCTIONS:
# Mosts resources have a "Service Resource" and can be found in the boto3 documentation under a given service. For example
# you can find the EC2 Service Resource here https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2.html?highlight=ec2#service-resource
# 
# These Service Resources have "collections", which are list of existing resources. For another example, if you wanted to
# get the existing Security Groups, you can do this:
# ec2 = boto3.resource('ec2')
# security_groups = list(ec2.security_groups.all())
#
# Each collection has a list of filters you can use to get only the resources you want. The security_groups collection used
# above can be found here https://boto3.amazonaws.com/v1/documentation/api/latest/reference/services/ec2.html?highlight=ec2#EC2.ServiceResource.security_groups
# along with the potential filters to be used on the collection.
#
# Collections in generally are more explained here https://boto3.amazonaws.com/v1/documentation/api/latest/guide/collections.html
# 
# For a full example, look at the aws_security_group_resource_generator function below.
#######################################################################################

# Helper function to generate a Terraform state from a given identifier and name
# "resource_id" is generally the main id on a given AWS resource
# "resource_name" is whatever you want the resource address to be in the Terraform config
def generate_resource_state(resource_id, resource_name):
    # Writing empty resource to file
    with open('empty-resources.tf', 'a') as outfile:
        outfile.write(inspect.cleandoc(f"""
        resource "{resource_type}" "{resource_name}" {{

        }}
        """))
        outfile.write('\n')
    # Running terraform import, to create a state file for the existing resource
    subprocess.run(['terraform', 'import', f"{resource_type}.{resource_name}", resource_id], stdout=subprocess.DEVNULL)


# Resource generator for the aws_security_group resource type
def aws_security_group_resource_generator():
    # Get existing AWS resources
    ec2 = boto3.resource('ec2')
    # TODO: Add to filter to remove inactive resources
    security_groups = list(ec2.security_groups.filter(Filters=[{'Name': 'vpc-id','Values': [vpc_id]}]))
    security_group_count = len(security_groups)

    # Loop through the existing resources and create an empty Terraform resource with the resource type and name
    for i, security_group in enumerate(security_groups):
        print(f"Importing aws_security_group: {i+1}/{security_group_count}", end = '\r')
        name = security_group.tags["Name"] if "Name" in security_group.tags else security_group.id
        generate_resource_state(security_group.id, name)
    print()


def aws_vpc_endpoint_resource_generator():
    # Get existing AWS resources
    client = boto3.client('ec2')
    
    response = client.describe_vpc_endpoints(
        # Filters=[
        #     {
        #         'Name': 'vpc-id',
        #         'Values': [
        #             vpc_id,
        #         ]
        #     },
        # ],
    )

    endpoints = list(response['VpcEndpoints'])
    endpoints_count = len(endpoints)
    for i, endpoint in enumerate(endpoints):
        print(f"Importing aws_vpc_endpoint: {i+1}/{endpoints_count}", end = '\r')
        # Generate the Terraform state, given the AWS resource ID, and a unique name
        generate_resource_state(endpoint['VpcEndpointId'], endpoint['ServiceName'].split('.')[-1])
    print()

# Resource generator for the aws_route_table resource type
def aws_route_table_resource_generator():
    # Get existing AWS resources
    ec2 = boto3.resource('ec2')
    # TODO: Add to filter to remove inactive resources
    route_tables = list(ec2.route_tables.filter(Filters=[{'Name': 'vpc-id','Values': [vpc_id]}]))
    route_table_count = len(route_tables)

    # Loop through the existing resources and create an empty Terraform resource with the resource type and name
    for i, route_table in enumerate(route_tables):
        print(f"Importing aws_route_table: {i+1}/{route_table_count}", end = '\r')
        name = route_table.tags["Name"] if "Name" in route_table.tags else route_table.id
        generate_resource_state(route_table.id, name)
    print()


# Main dictionary that manages all the resource types
resource_types = {
    "aws_security_group": {
        # Attributes that you want to be in the Terraform config
        "desired_attributes": {
            'name': None,
            'description': None,
            'vpc_id': None,
            'tags': None,
            'ingress': {
                'from_port': None,
                'to_port': None,
                'protocol': None,
                'cidr_blocks': None,
                'description': None,
                'ipv6_cidr_blocks': None,
                'prefix_list_ids': None,
                'security_groups': None,
                'self': None
            }
        },
        # Function used to generate the list of existing AWS resources to be imported into Terraform
        "resource_generator": aws_security_group_resource_generator
    },
    "aws_vpc_endpoint": {
        "desired_attributes": {
            'service_name': None,
            'vpc_id': None,
            'vpc_endpoint_type': None,
            'subnet_ids': None,
            'route_table_ids': None,
            'security_group_ids': None,
            'private_dns_enabled': None,
            'tags': None
        },
        "resource_generator": aws_vpc_endpoint_resource_generator
    },
    "aws_route_table": {
        "desired_attributes": {
            'vpc_id': None,
            'tags': None,
            'propagating_vgws': None,
            'route': {
                'cidr_block': None,
                'ipv6_cidr_block': None,
                'destination_prefix_list_id': None,
                'carrier_gateway_id': None,
                'egress_only_gateway_id': None,
                'gateway_id': None,
                'instance_id': None,
                'local_gateway_id': None,
                'nat_gateway_id': None,
                'network_interface_id': None,
                'transit_gateway_id': None,
                'vpc_endpoint_id': None,
                'vpc_peering_connection_id': None
            }
            },  
            "resource_generator": aws_route_table_resource_generator
        },
}

#############################################################
#############################################################
#############################################################



# No need to change any of this code....

if __name__ == '__main__':
    # Removing files to start fresh
    if os.path.exists('main.tf'): os.remove('main.tf')
    if os.path.exists('terraform.tfstate'): os.remove('terraform.tfstate')
    if os.path.exists('terraform.tfstate.backup'): os.remove('terraform.tfstate.backup')

    # Writing AWS provider to config file
    with open('empty-resources.tf', 'w') as outfile:
        outfile.write(f'provider "aws" {{\nprofile = "{aws_profile}"\nregion = "{region}"\nshared_credentials_file = "/cloud/aws/credentials"\n}}\n')

    # Initialize terraform after specifying the aws plugin
    print('Initializing Terraform')
    subprocess.run(['terraform', 'init'], stdout=subprocess.DEVNULL)

    # Run resource generator for specific resource type
    resource_types[resource_type]["resource_generator"]()

    # Remove files that are no longer needed
    if os.path.exists('empty-resources.tf'): os.remove('empty-resources.tf')
    if os.path.exists('terraform.tfstate.backup'): os.remove('terraform.tfstate.backup')

    # Get existing state data
    state_data = {}
    with open('terraform.tfstate') as json_file:
        state_data = json.load(json_file)

    # Iterate through all the resources in the state data and keep only the desired attributes
    def clean_state_section(attributes, desired_attributes):
        keys_to_delete = []
        for attribute in attributes:
            if attribute not in desired_attributes:
                keys_to_delete.append(attribute)
            else:
                if desired_attributes[attribute] != None:
                    # Repeat for nested state attributes
                    if (isinstance(attributes[attribute], list)):
                        for element in attributes[attribute]:
                            clean_state_section(element, desired_attributes[attribute])
                    else:
                        clean_state_section(attributes[attribute], desired_attributes[attribute])

        for key in keys_to_delete:
            attributes.pop(key)

    print('Generating terraform configuration')
    for resource in state_data['resources']:
        clean_state_section(resource['instances'][0]['attributes'], resource_types[resource_type]["desired_attributes"])

    # Save the original state for later
    os.rename('terraform.tfstate', 'originalstate')

    # Write modified state back to file
    with open('terraform.tfstate', 'w') as outfile:
        json.dump(state_data, outfile, indent=2)

    # Create config from state file
    with open('main.tf', 'w') as outfile:
        # Writing AWS provider to config file
        outfile.write(inspect.cleandoc(f"""
        provider "aws" {{
            profile = "{aws_profile}"
            region = "{region}"
            shared_credentials_file = "/cloud/aws/credentials"
        }}
        """))
        outfile.write("\n\n")
        # This command basically takes the whole state, and outputs it in config form
        outfile.write(subprocess.run(['terraform', 'show', '-no-color'], capture_output=True, text=True).stdout)

    # Remove state file used to create the config and then restore the original state
    os.remove('terraform.tfstate')
    os.rename('originalstate', 'terraform.tfstate')

    # See if the config that's made is in correct form
    subprocess.run(['terraform', 'fmt'], stdout=subprocess.DEVNULL)
    subprocess.run(['terraform', 'validate'])
    subprocess.run(['terraform', 'plan'])
