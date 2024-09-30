# RISE Demo Terraform Deployment

## Overview

This README provides a guide on deploying the RISE application and its dependencies on an AWS EC2 instance using Terraform. The deployment includes setting up IAM roles, security groups, and an EC2 instance with the necessary software, Docker containers, a systemd service called rise-app that will run the applications via docker compose. nce the application is up and running, the run_sfincs.sh script is executed in the EC2 instance's user_data, and the output is pushed to S3.

The configurations supports AWS and is meant to be extendable to optionally support deployment to Azure and GCP in the future.

Only the AWS code has been run in NGWPC environments, and multiple considerations are left for the deployer at this early stage around providing an appropriate config with regard to S3 access and execution after the first run.  It is very likely that the future iterations of any deployment for rise will look different from this MVP.

## Prerequisites

- [Terraform](https://www.terraform.io/downloads.html) installed.
- Appropriate, configured cloud provider credentials. This does interact with IAM, so it requires Admin level privileges.
- An existing VPC and subnet in the AWS region you plan to deploy.
- Available Rocky 9 AMI. A similar RHEL or CentOS based AMI should work with minor changes to the user_data. An Ubuntu based AMI would require more with a change to APT based package management.
- S3 Bucket containing the required input data to be copied to: /app/rise/data prior to starting the application.

## Base Configuration and Deploy

### Configuration (variables)

To streamline the deployment process and avoid being prompted for every variable, you can create a terraform.tfvars file to predefine values for the target-specific variables in your Terraform configuration. This file allows you to set values for variables such as region, vpc_id, subnet_id, instance_type, rocky_linux_ami_id, git_repo_url, git_branch, and rise_s3_bucket. By populating the terraform.tfvars file with these values, Terraform will automatically use them during the deployment, ensuring consistency across environments and eliminating the need for manual input. 

Simply create the terraform.tfvars file in the root directory of your Terraform project, and add entries like region = "us-east-1", vpc_id = "vpc-xxxxxx", ETC., corresponding to the variables you want to set. A common practice in Terraform to manage different configurations for various environments such as development, staging, and production is to create multiple tfvars files and target them per environment. For each environment, create a separate .tfvars file. For example:

- test.tfvars
- oe.tfvars

Each of these files would contain the variables specific to that environment, and when deploying, you can target the specific environment variable file by leveraging the -var-file flag.

### Cloud Service Provider Terraform Configuration and Deploy

We've only been working with AWS thus far, so we'll focus on that configuration.

## Usage

### AWS

1. Navigate to the appropriate Cloud Service Provider directory:

    There are a lot of questions that need to be answered around targettin existing OWP internal resources (RDBMS & Object Storage: S3) if deploying to a Cloud Service Provider other than AWS.  Docker Compose based deploys are technically compatible with any host of sufficient size running an appropriate version of Docker with the Docker Compose plugin, but the deployed applications still needthe same access to pre-requisite services in OWPs existing environment or equivalent copies need to be created in the target CSP.

    ```sh
    # Currently supported
    cd aws

    # Potential Future Targets
    cd gcp
    cd azure
    ```

2. Update or create a variables.tfvars file with values appropriate for your targeted deployment as described in the generic configuration instructions.

    See below for an explanation of each variables listed.

    env = "test":
    - Purpose: Specifies the environment for which this configuration is intended.
    - Details: In this case, the environment is labeled as "test", which might be used to distinguish it from other environments like "dev", "test", or "oe". This variable can be used in naming conventions for resources that are created to ensure they are environment-specific.

    region = "us-east-1":
    - Purpose: Defines the AWS region where the resources will be deployed.
    - Details: us-east-1 corresponds to the N. Virginia region, one of the most commonly used regions due to its extensive AWS services availability.
    
    vpc_id = "vpc-xxxxxxxxxxxxxxx":
    - Purpose: Specifies the ID of the Virtual Private Cloud (VPC) where the resources will be created.
    - Details: This VPC is a logically isolated section of the AWS cloud where you can launch AWS resources in a virtual network that you define.
    
    subnet_id = "subnet-xxxxxxxxxxxxxx":
    - Purpose: Identifies the specific subnet within the VPC where the EC2 instance will be launched.
    - Details: Subnets are segments of a VPC’s IP address range where resources are placed. This subnet should be associated with an availability zone within the specified region.
    
    instance_type = "c5a.8xlarge":
    - Purpose: Determines the type of EC2 instance to launch.
    - Details: c5a.8xlarge is a compute-optimized instance type, providing a good balance of compute power and memory for applications that require up to 32 vCPUs and 64 GiB RAM, such as RISE.
    
    ebs_volume_size = 20:
    - Purpose: Specifies the size (in GB) of the Elastic Block Store (EBS) volume attached to the instance.
    - Details: This storage volume is used for data persistence. A 20 GB volume should be sufficient for testing purposes, depending on the application’s data requirements.
    
    rise_s3_bucket = "ngwpc-rise-test":
    - Purpose: Defines the name of the S3 bucket where the application will store and retrieve data. This terraform creates a role with appropriate access granted to the bucket name provided here. Note that this will only work if the bucket is in the same account as your deployment. Modifications will need to be made to support multi-account architectures leveraging sts assume role logic.
    - Details: This S3 bucket is specific to the test environment and is used by RISE to store input and output files.
    
    extra_policy_arn = "arn:aws:iam::xxxxxxxxx:policy/AWSAccelerator-SessionManagerLogging":
    - Purpose: Adds an additional IAM policy to the instance role.
    - Details: (Optional) This specific policy is necessary for enabling AWS Systems Manager (SSM) session manager logging in the NGWPC environments, allowing for secure remote access and session logging.  You could use this to attach any policy required in your account in addition to the one created by this terraform for S3 access. If you leave this variable out of your config or blank, nothing will be added.
    
    git_repo_url = "https://github.com/taddyb33/rise.git"
    - Purpose: Indicates the Git Repo that should be used when cloning the application repository.
    - Details: (Optional) This value defaults to: https://github.com/taddyb33/rise.git, but you might need to change it should you be running this from a Fork of that repo or if this repo has been merged or moved in your environment.

    git_branch = "development":
    - Purpose: Indicates which Git branch should be used when cloning the application repository.
    - Details: The "development" branch is likely where active development and testing occur, making it suitable for the test environment, while main or a specific tag would be more appropriate for a production or production like environment.

    rocky_linux_ami_id = "ami-09fb459fad4613d55":
    - Purpose: Specifies the Amazon Machine Image (AMI) ID used to launch the EC2 instance.
    - Details: This AMI ID corresponds to a Rocky 9 Linux image. This specific ID points to a version that’s appropriate for the region us-east-1, but you must subscribe to the official Rocky AMIs. They do not currently charge any fee on top of your EC2 costs.


3. Initialize Terraform:
    ```sh
    terraform init
    ```
4. Review the Terraform plan (targetting your specific tfvars file):
    ```sh
    terraform plan -var-file=test.tfvars
    ```

4. Apply the Terraform configuration (targetting your specific tfvars file):
    ```sh
    terraform apply -var-file=test.tfvars
    ```

### Azure
Modify the variables.tf file to specify the appropriate values for your environment, such as location, resource_group_name, vm_size, subnet_id
### GCP
Modify the variables.tf file to specify the appropriate values for your environment, such as project, region, zone, vm_name, vm_machine_type, subnetwork, network, image_project, image_family

## Cleaning Up
To destroy the resources created by Terraform, navigate to the respective directory and run:

```sh
terraform destroy -var-file=test.tfvars
```

### Notes
Ensure that you have the necessary IAM permissions to create and manage resources in your cloud environment.
This configuration does not assign a public IP to the VMs. Access should be managed through a VPN or bastion host.
The user data specifically starts the applications and executes sfincs one time.  There is currently no reason to leave this running after the process has completed or you have finished manually interacting with the application.

## AWS Terraform Walkthrough

This serves as a brief walkthrough of the fairly simple provided Terraform solution. Ideally, this is enough information to help with any changes or customizations required to deploy to your environment.

### Provider Configuration: 
The Terraform AWS provider is configured with the region specified in the variable var.region.

### IAM Role and Instance Profile
The IAM role is assigned to the EC2 instance, allowing it to interact with AWS services like S3. The following resources are created:
- IAM Role: Grants the EC2 instance permission to assume the role.
- IAM Policy: Grants S3 access for syncing application data.
- Instance Profile: Associates the IAM role with the EC2 instance.

### Security Group
A security group is created to allow SSH access and open the necessary ports for the application and services.  Specific required ports are still TBD as this is meant to run without intervention or any interface.

### EC2 Instance
The EC2 instance is configured via the instance user_date with necessary software including Docker, Docker Compose and the AWS CLI. It will automatically clone the rise application code, sync data from S3, and start the services defined in the Docker Compose configuration via a systemd service called rise-app. The app(s) can be stopped and started similarly via systemctl stop and start.

## Cost Considerations

This reference deployment creates the following resources. Price estimates provided for us-east-1, but note that they are very rough guesses accounting for far more data than is currently being used for this demonstration, and that the instance and EBS volume should be torn down after use rather than incur needless cost. This will change considerably with real data and persistent resource.

c5a.8xlarge On Demand   $1.232/Hour

    1 instances x 1.232 USD On Demand hourly cost x 1 hours in a month = 1.232000 USD
    On-Demand instances (monthly): 1.232000 USD

EBS 20 GB   $0.00 per month (this is effectively $0 in this use case where there is no requirement for persistent storage)

    3,000 iops / 20 GB = 150.00 IOPS to GB ratio (gp3)
    125 MBps / 3,000 iops = 0.04 IOPS to Throughput ratio
    1 volumes x 1 instance hours = 1.00 total instance hours
    1.00 instance hours / 730 hours in a month = 0.00 instance months
    EBS Storage Cost: 0 USD
    3,000 iops - 3000 GP3 iops free = 0.00 billable gp3 iops
    EBS IOPS Cost: 0.00 USD
    125 MBps - 125 GP3 MBps free = 0.00 billable MBps
    EBS Snapshot Cost: 0 USD
    Amazon Elastic Block Storage (EBS) total cost (monthly): 0.00 USD


S3  20 GB   $0.46 per month

    20 GB x 0.023 USD = 0.46 USD
    Total tier cost = 0.46 USD (S3 Standard storage cost)
    100 PUT requests for S3 Standard Storage x 0.000005 USD per request = 0.0005 USD (S3 Standard PUT requests cost)
    100 GET requests in a month x 0.0000004 USD per request = 0.00 USD (S3 Standard GET requests cost)
    20 GB x 0.0007 USD = 0.014 USD (S3 select returned cost)
    0.46 USD + 0.0005 USD + 0.014 USD = 0.47 USD (Total S3 Standard Storage, data requests, S3 select cost)
