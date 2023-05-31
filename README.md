# Overview

The Hydrologic Visualization and Information Services (HydroVIS) project aims to process and disseminate hydrologic data through the AWS public cloud. The HydroVIS visualization process pipeline (VPP) ingests forecast data from the National Water Model (NWM) and River Forecasting Centers (RFC), analyzes the data, and then creates products and services that are disseminated through an AWS hosted GIS platform.

This repo contains all the infrastructure as code (IaC) used to create and setup AWS services for the HydroVIS VPP.

<br/>
<br/>

## Terms
- `ENV` - The name of the environment you are deploying to e.g `prod`.
- `REGION` - The AWS Region you are deploying to e.g `us-east-1`.
- `TF_STATE_ENV` - The name of the environment that your Terraform Remote State is stored in.

<br/>

# Usage


<details>
<summary>
  Dependencies
</summary> <br />

- `terraform (v1.2.0+)`
- `aws-cli (v2.5.6+)`
</details>

<details>
<summary>
  Initial Setup
</summary> <br />

Before you can perform deployments to the HydroVIS environment you will need to do the following:

### Setting up the Codebase
1. Clone this repository to your deployment machine.
2. Clone the private ENV storage repository into a folder called `sensitive` at the root of your local copy of this repository.

### Setting up the AWS CLI
1. Download and Install the [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html)
2. You will need to configure an AWS profile for each of the corresponding `ENV_REGION` combination you will be deploying to. [Here](https://docs.aws.amazon.com/cli/latest/userguide/sso-configure-profile-token.html) are the instuctions on how to set up AWS CLI profiles to use SSO credentials. Simply follow the instructions and name the profiles as the environment and region names.

### Setting up Terraform
1. Download and Install the [Terraform](https://developer.hashicorp.com/terraform/tutorials/aws-get-started/install-cli#install-cli) CLI tool.
2. Navigate to `/Core` in your local copy of this repository.
3. Run `aws sso login --profile TF_STATE_ENV`.
4. Run `terraform init`. This will initialize the remote state backend to give you access to the terraform workspaces for all the cloud environments.

</details>

<br/>

The following is the deployment process for updating a given HydroVIS environment. The steps are identical regardless of which environment you are deploying to.
- `$ git checkout ENV`
- `$ git pull`
- `$ aws sso login --profile TF_STATE_ENV`
- `$ terraform workspace select ENV_REGION`
- `$ terraform init`
- `$ terraform plan -out buildplan`
- Review the console output to see all the changes that will be made to the environment. If there is too much output to read through, a good way to get a summary of the Terraform plan would be to run something similar to `terraform plan -out buildplan | Select-String "# module"`.
- `$ terraform apply "buildplan"`

<br/>

# Troubleshooting

Generally, Terraform is very good at telling you where exactly an issue is when you run the `terraform plan` command. Simply go to the file and line number provided in the console output and investigate. Terraform has excellent documentation, so you can go to the AWS Provider documentation [here](https://registry.terraform.io/providers/hashicorp/aws/latest/docs) to get details on all of the terraform resources.

If Terraform fails during the `terraform apply` command, first try re-running the `plan` and `apply` commands to see if the issue resolves itself. This issue sometimes happens due to race-conditions on Terraform resource dependencies.

<br/>

## Specific Errors
### `Error: error configuring S3 Backend: no valid credential sources for S3 Backend found.`

Description: This error message means that you need to re-authenticate with the AWS environment that stores the Terraform Remote State.

Solution: `$ aws sso login --profile TF_STATE_ENV`

<br/>
<br/>

# Development

The workflow for developing new features in HydroVIS is as follows:

- Create a new feature branch from the existing `ti` branch.
- Navigate to the `/Dev` folder.
- Copy `env-example.yaml` to `env.yaml` and fill it out with the environment variables.
- Using the `main.tf` as a template, create Data Sources to relevant existing AWS resources and create the new resources for your feature.
- Deploy and test your new features.
  - `$ aws sso login --profile ENV`
  - `$ terraform init`
  - `$ terraform plan -out buildplan`
  - Review changes that will be made to the AWS environment
  - `$ terraform apply "buildplan"`

- Once development is finished, re-integrate the new resources in the `Dev` folder into the `/Core` folder and reset the `/Dev` folder back to how it was originally.
- Create a pull request to have your new feature branch merged into the `ti` branch.
