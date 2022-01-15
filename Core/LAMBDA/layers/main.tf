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
  s3_bucket = var.lambda_data_bucket
  s3_key    = "lambda_layers/es_logging.zip"

  layer_name = "es_logging_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "Custom logger that formats logs for AWS elasticsearch ingest"
}

#######################################
## Viz Lambda Shared Functions Layer ##
#######################################

resource "aws_lambda_layer_version" "viz_lambda_shared_funcs" {
  s3_bucket = var.lambda_data_bucket
  s3_key    = "lambda_layers/viz_lambda_shared_funcs.zip"

  layer_name = "viz_lambda_shared_funcs_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "Helper functions for general viz lambda functionality"
}

#############################
## ArcGIS Python API Layer ##
#############################

resource "aws_lambda_layer_version" "arcgis_python_api" {
  s3_bucket = var.lambda_data_bucket
  s3_key    = "lambda_layers/arcgis_python_api.zip"

  layer_name = "arcgis_python_api_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "ArcGIS Python API module"
}

########################
## MRF Rasterio Layer ##
########################

resource "aws_lambda_layer_version" "mrf_rasterio" {
  s3_bucket = var.lambda_data_bucket
  s3_key    = "lambda_layers/mrf_rasterio.zip"

  layer_name = "mrf_rasterio_${var.environment}"

  compatible_runtimes = ["python3.6"]
  description         = "Rasterio python package with MRF enabled"
}

###########################
## Multiprocessing Layer ##
###########################

resource "aws_lambda_layer_version" "multiprocessing" {
  s3_bucket = var.lambda_data_bucket
  s3_key    = "lambda_layers/multiprocessing.zip"

  layer_name = "multiprocessing_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7"]
  description         = "Multiprocessing python package"
}

##################
## Pandas Layer ##
##################

resource "aws_lambda_layer_version" "pandas" {
  s3_bucket = var.lambda_data_bucket
  s3_key    = "lambda_layers/pandas.zip"

  layer_name = "pandas_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7"]
  description         = "pandas python package"
}

####################
## Psycopg2 Layer ##
####################

resource "aws_lambda_layer_version" "psycopg2" {
  s3_bucket = var.lambda_data_bucket
  s3_key    = "lambda_layers/psycopg2.zip"

  layer_name = "psycopg2_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "psycopg2 python package"
}

####################
## Rasterio Layer ##
####################

resource "aws_lambda_layer_version" "rasterio" {
  s3_bucket = var.lambda_data_bucket
  s3_key    = "lambda_layers/rasterio.zip"

  layer_name = "rasterio_${var.environment}"

  compatible_runtimes = ["python3.6"]
  description         = "rasterio python package"
}

##################
## Xarray Layer ##
##################

resource "aws_lambda_layer_version" "xarray" {
  s3_bucket = var.lambda_data_bucket
  s3_key    = "lambda_layers/xarray.zip"

  layer_name = "xarray_${var.environment}"

  compatible_runtimes = ["python3.7"]
  description         = "xarray python package"
}

################
## Pika Layer ##
################

resource "aws_lambda_layer_version" "pika" {
  s3_bucket = var.lambda_data_bucket
  s3_key    = "ingest/lambda/layers/pika.zip"

  layer_name = "pika_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "Python pika module"
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

output "mrf_rasterio" {
  value = resource.aws_lambda_layer_version.mrf_rasterio
}

output "multiprocessing" {
  value = resource.aws_lambda_layer_version.multiprocessing
}

output "pandas" {
  value = resource.aws_lambda_layer_version.pandas
}

output "psycopg2" {
  value = resource.aws_lambda_layer_version.psycopg2
}

output "rasterio" {
  value = resource.aws_lambda_layer_version.rasterio
}

output "xarray" {
  value = resource.aws_lambda_layer_version.xarray
}

output "pika" {
  value = resource.aws_lambda_layer_version.pika
}
