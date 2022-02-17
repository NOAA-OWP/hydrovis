# HydroViz Development & Operations of Infrastructure as Code

This repository should contain all the information about the system, to ensure that any change  (source code, documentation, policies, users etc.) is tracked.

The main folder that holds the infrastructure for the ti/uat/prod environments is the `Core` folder. The `Dev` folder is utilized to develop new features which will be later integrated into the `Core` folder. Finally, the `Scripts` folder is a collection of helper scripts to aid in importing existing resources into Terraform configurations and other tasks.

# Initial Setup

In order to use this repository, you need to do the following:

 - Clone this repository.
 - Copy the `sentitive` data folder from other location into the `Core` folder of this repo.
 - Install the AWS CLI tools and Terraform onto your machine.
 - Follow the instructions found [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html) and [here](https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-profiles.html) to get aws profiles set up for the ti/uat/prod environments.
 - Run `terraform init` in the `Core` folder to get everything initialized.


# Developing new features

The workflow for developing new features in Hydrovis is as follows:

 - Create a new feature branch from the existing `ti` branch.
 - Copy relevant resources from the `Core` folder into the `Dev` folder and/or use the existing `Dev/main.tf` as a template for a new feature module.
 - Fill out the `Dev/sensitive/envs/env.dev.yaml` with the relevant information.
 - Deploy and test your new features.
 - Once development is finished, reintegrate the resources in the `Dev` folder into the `Core` folder and reset the `Dev` folder back to how it was originally.
 - Create a pull request to have your new feature branch merged into the `ti` branch.
