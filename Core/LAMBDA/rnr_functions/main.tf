terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      configuration_aliases = [ aws.sns ]
    }
  }
}

variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "region" {
  description = "Hydrovis environment"
  type        = string
}

variable "deployment_bucket" {
  type = string
}

variable "db_lambda_security_groups" {
  description = "Security group for the rnr lambdas."
  type        = list(any)
}

variable "db_lambda_subnets" {
  description = "Subnets to use for the rnr lambdas."
  type        = list(any)
}

variable "viz_db_host" {
  description = "Hostname of the viz processing RDS instance."
  type        = string
}

variable "viz_db_name" {
  description = "DB Name of the viz processing RDS instance."
  type        = string
}

variable "viz_db_user_secret_string" {
  description = "The secret string of the viz_processing data base user to write/read data as."
  type        = string
}

variable "rnr_data_bucket" {
  description = "S3 bucket where the rnr max flows will live."
  type        = string
}

variable "lambda_role" {
  description = "Role to use for the lambda functions."
  type        = string
}

variable "xarray_layer" {
  type = string
}

variable "psycopg2_sqlalchemy_layer" {
  type = string
}

variable "viz_lambda_shared_funcs_layer" {
  type = string
}

#############################
##    REPLACE AND ROUTE    ##
#############################
data "archive_file" "rnr_domain_generator_zip" {
  type = "zip"

  source_dir = "${path.module}/rnr_domain_generator"

  output_path = "${path.module}/temp/rnr_domain_generator_${var.environment}_${var.region}.zip"
}

resource "aws_s3_object" "rnr_domain_generator_zip_upload" {
  tags = {}
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/rnr_domain_generator.zip"
  source      = data.archive_file.rnr_domain_generator_zip.output_path
  source_hash = data.archive_file.rnr_domain_generator_zip.output_md5
}

resource "aws_lambda_function" "rnr_domain_generator" {
  function_name = "hv-vpp-${var.environment}-rnr-domain-generator"
  description   = "Lambda function to run Replace and Route model."
  memory_size   = 512
  timeout       = 900
  vpc_config {
    security_group_ids = var.db_lambda_security_groups
    subnet_ids         = var.db_lambda_subnets
  }
  environment {
    variables = {
      VIZ_DB_DATABASE = var.viz_db_name
      VIZ_DB_HOST     = var.viz_db_host
      VIZ_DB_USERNAME = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD = jsondecode(var.viz_db_user_secret_string)["password"]
      OUTPUT_BUCKET   = var.rnr_data_bucket
      OUTPUT_PREFIX   = "rnr_runs"
    }
  }
  s3_bucket        = aws_s3_object.rnr_domain_generator_zip_upload.bucket
  s3_key           = aws_s3_object.rnr_domain_generator_zip_upload.key
  source_code_hash = filebase64sha256(data.archive_file.rnr_domain_generator_zip.output_path)
  runtime          = "python3.9"
  handler          = "lambda_function.lambda_handler"
  role             = var.lambda_role
  layers = [
    var.xarray_layer,
    var.psycopg2_sqlalchemy_layer,
    var.viz_lambda_shared_funcs_layer
  ]
  tags = {
    "Name" = "rnr_domain_generator_${var.environment}"
  }
}

output "rnr_domain_generator" {
  value = aws_lambda_function.rnr_domain_generator
}