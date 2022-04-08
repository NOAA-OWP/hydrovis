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

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "Helper functions for general viz lambda functionality"
}

#############################
## ArcGIS Python API Layer ##
#############################

resource "aws_lambda_layer_version" "arcgis_python_api" {
  filename         = "${path.module}/arcgis_python_api.zip"
  source_code_hash = filebase64sha256("${path.module}/arcgis_python_api.zip")

  layer_name = "arcgis_python_api_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "ArcGIS Python API module"
}

########################
## MRF Rasterio Layer ##
########################

resource "aws_lambda_layer_version" "mrf_rasterio" {
  filename         = "${path.module}/mrf_rasterio.zip"
  source_code_hash = filebase64sha256("${path.module}/mrf_rasterio.zip")

  layer_name = "mrf_rasterio_${var.environment}"

  compatible_runtimes = ["python3.6"]
  description         = "Rasterio python package with MRF enabled"
}

###########################
## Multiprocessing Layer ##
###########################

resource "aws_lambda_layer_version" "multiprocessing" {
  filename         = "${path.module}/multiprocessing.zip"
  source_code_hash = filebase64sha256("${path.module}/multiprocessing.zip")

  layer_name = "multiprocessing_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7"]
  description         = "Multiprocessing python package"
}

##################
## Pandas Layer ##
##################

resource "aws_lambda_layer_version" "pandas" {
  filename         = "${path.module}/pandas.zip"
  source_code_hash = filebase64sha256("${path.module}/pandas.zip")

  layer_name = "pandas_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7"]
  description         = "pandas python package"
}

##################################
## Psycopg2 & SQL Alchemy Layer ##
##################################

resource "aws_lambda_layer_version" "psycopg2_sqlalchemy" {
  filename         = "${path.module}/psycopg2_sqlalchemy.zip"
  source_code_hash = filebase64sha256("${path.module}/psycopg2_sqlalchemy.zip")

  layer_name = "psycopg2_sqlalchemy_${var.environment}"

  compatible_runtimes = ["python3.6", "python3.7", "python3.8"]
  description         = "psycopg2 and sql alchemy python packages"
}

####################
## Rasterio Layer ##
####################

resource "aws_lambda_layer_version" "rasterio" {
  filename         = "${path.module}/rasterio.zip"
  source_code_hash = filebase64sha256("${path.module}/rasterio.zip")

  layer_name = "rasterio_${var.environment}"

  compatible_runtimes = ["python3.6"]
  description         = "rasterio python package"
}

##################
## Xarray Layer ##
##################

resource "aws_lambda_layer_version" "xarray" {
  filename         = "${path.module}/xarray.zip"
  source_code_hash = filebase64sha256("${path.module}/xarray.zip")

  layer_name = "xarray_${var.environment}"

  compatible_runtimes = ["python3.7"]
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

output "psycopg2_sqlalchemy" {
  value = resource.aws_lambda_layer_version.psycopg2_sqlalchemy
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
