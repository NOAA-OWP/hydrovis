variable "environment" {
  description = "Hydrovis environment"
  type        = string
}

variable "viz_environment" {
  description = "Visualization environment for code that should be used."
  type        = string
}

variable "lambda_data_bucket" {
  description = "S3 buckets where the lambda zip files will live."
  type        = string
}

######################
## ES Logging Layer ##
######################

resource "aws_lambda_layer_version" "es_logging" {
  filename         = "${path.module}/es_logging.zip"
  source_code_hash = filebase64sha256("${path.module}/es_logging.zip")

  layer_name = "es_logging_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "Custom logger that formats logs for AWS elasticsearch ingest"
}

#######################################
## Viz Lambda Shared Functions Layer ##
#######################################

resource "aws_lambda_layer_version" "viz_lambda_shared_funcs" {
  filename         = "${path.module}/viz_lambda_shared_funcs.zip"
  source_code_hash = filebase64sha256("${path.module}/viz_lambda_shared_funcs.zip")

  layer_name = "viz_lambda_shared_funcs_${var.environment}"

  compatible_runtimes = ["python3.7", "python3.8"]
  description         = "Viz classes and helper functions for general viz lambda functionality"
}

#############################
## ArcGIS Python API Layer ##
#############################

resource "aws_s3_object" "arcgis_python_api" {
  bucket = var.lambda_data_bucket
  key    = "lambda_layers/arcgis_python_api.zip"
  source = "${path.module}/arcgis_python_api.zip"
  source_hash = filemd5("${path.module}/arcgis_python_api.zip")
}

resource "aws_lambda_layer_version" "arcgis_python_api" {
  s3_bucket = aws_s3_object.arcgis_python_api.bucket
  s3_key = aws_s3_object.arcgis_python_api.key

  layer_name = "arcgis_python_api_${var.environment}"

  compatible_runtimes = ["python3.9"]
  description         = "ArcGIS Python API module"
}

##################
## Pandas Layer ##
##################

resource "aws_lambda_layer_version" "pandas" {
  filename         = "${path.module}/pandas.zip"
  source_code_hash = filebase64sha256("${path.module}/pandas.zip")

  layer_name = "pandas_${var.environment}"

  compatible_runtimes = ["python3.9"]
  description         = "pandas python package"
}

##################
## GeoPandas Layer ##
##################

resource "aws_lambda_layer_version" "geopandas" {
  filename         = "${path.module}/geopandas.zip"
  source_code_hash = filebase64sha256("${path.module}/geopandas.zip")

  layer_name = "geopandas_${var.environment}"

  compatible_runtimes = ["python3.9"]
  description         = "geopandas python package"
}

##################################
## Psycopg2 & SQL Alchemy Layer ##
##################################

resource "aws_lambda_layer_version" "psycopg2_sqlalchemy" {
  filename         = "${path.module}/psycopg2_sqlalchemy.zip"
  source_code_hash = filebase64sha256("${path.module}/psycopg2_sqlalchemy.zip")

  layer_name = "psycopg2_sqlalchemy_${var.environment}"

  compatible_runtimes = ["python3.9"]
  description         = "psycopg2 and sql alchemy python packages"
}

##########################
## HUC Proc Combo Layer ##
##########################

resource "aws_s3_object" "huc_proc_combo" {
  bucket = var.lambda_data_bucket
  key    = "lambda_layers/huc_proc_combo.zip"
  source = "${path.module}/huc_proc_combo.zip"
  source_hash = filemd5("${path.module}/huc_proc_combo.zip")
}

resource "aws_lambda_layer_version" "huc_proc_combo" {
  s3_bucket = aws_s3_object.huc_proc_combo.bucket
  s3_key = aws_s3_object.huc_proc_combo.key

  layer_name = "huc_proc_combo_${var.environment}"

  compatible_runtimes = ["python3.9"]
  description         = "Includes pandas, pyscopg2, sqlachemy, and rasterio"
}

##################
## Xarray Layer ##
##################

resource "aws_lambda_layer_version" "xarray" {
  filename         = "${path.module}/xarray.zip"
  source_code_hash = filebase64sha256("${path.module}/xarray.zip")

  layer_name = "xarray_${var.environment}"

  compatible_runtimes = ["python3.9"]
  description         = "xarray python package"
}

################
## Pika Layer ##
################

resource "aws_lambda_layer_version" "pika" {
  filename         = "${path.module}/pika.zip"
  source_code_hash = filebase64sha256("${path.module}/pika.zip")

  layer_name = "pika_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "Python pika module"
}

####################
## Requests Layer ##
####################

resource "aws_lambda_layer_version" "requests" {
  filename         = "${path.module}/requests.zip"
  source_code_hash = filebase64sha256("${path.module}/requests.zip")

  layer_name = "requests_${var.environment}"

  compatible_runtimes = ["python3.9"]
  description         = "Python requests module"
}

#############
## Outputs ##
#############

output "es_logging" {
  value = resource.aws_lambda_layer_version.es_logging
}

output "viz_lambda_shared_funcs" {
  value = resource.aws_lambda_layer_version.viz_lambda_shared_funcs
}

output "arcgis_python_api" {
  value = resource.aws_lambda_layer_version.arcgis_python_api
}

output "pandas" {
  value = resource.aws_lambda_layer_version.pandas
}

output "geopandas" {
  value = resource.aws_lambda_layer_version.geopandas
}

output "psycopg2_sqlalchemy" {
  value = resource.aws_lambda_layer_version.psycopg2_sqlalchemy
}

output "huc_proc_combo" {
  value = resource.aws_lambda_layer_version.huc_proc_combo
}

output "xarray" {
  value = resource.aws_lambda_layer_version.xarray
}

output "pika" {
  value = resource.aws_lambda_layer_version.pika
}

output "requests" {
  value = resource.aws_lambda_layer_version.requests
}
