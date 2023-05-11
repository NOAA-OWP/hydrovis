variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "deployment_bucket" {
  type = string
}

variable "raster_output_bucket" {
  type = string
}

variable "raster_output_prefix" {
  type = string
}

variable "lambda_role" {
  type = string
}

variable "hand_fim_processing_sgs" {
  type = list(string)
}

variable "hand_fim_processing_subnets" {
  type = list(string)
}

variable "ecr_repository_image_tag" {
  type = string
}

variable "fim_version" {
  type = string
}

variable "max_values_bucket" {
  type = string
}

variable "fim_data_bucket" {
  type = string
}

variable "viz_db_name" {
  type = string
}

variable "viz_db_host" {
  type = string
}

variable "viz_db_user_secret_string" {
  type = string
}

variable "egis_db_name" {
  type = string
}

variable "egis_db_host" {
  type = string
}

variable "egis_db_user_secret_string" {
  type = string
}

locals {
  viz_optimize_rasters_lambda_name = "viz_optimize_rasters_${var.environment}"
  viz_hand_fim_processing_lambda_name = "viz_hand_fim_processing_${var.environment}"
  viz_schism_fim_processing_lambda_name = "viz_schism_fim_processing_${var.environment}"
  viz_raster_processing_lambda_name = "viz_raster_processing_${var.environment}"
}

##############################
## RASTER PROCESSING LAMBDA ##
##############################

data "archive_file" "raster_processing_zip" {
  type = "zip"
  output_path = "${path.module}/viz_raster_processing_${var.environment}.zip"

  dynamic "source" {
    for_each = fileset("${path.module}/viz_raster_processing/products", "*")
    content {
      content  = file("${path.module}/viz_raster_processing/products/${source.key}")
      filename = "products/${source.key}"
    }
  }

  dynamic "source" {
    for_each = fileset("${path.module}/viz_raster_processing", "*")
    content {
      content  = file("${path.module}/viz_raster_processing/${source.key}")
      filename = source.key
    }
  }
  source {
    content  = file("${path.module}/../../layers/viz_lambda_shared_funcs/python/viz_classes.py")
    filename = "viz_classes.py"
  }
  source {
    content  = file("${path.module}/../../layers/viz_lambda_shared_funcs/python/viz_lambda_shared_funcs.py")
    filename = "viz_lambda_shared_funcs.py"
  }
}

resource "aws_s3_object" "raster_processing_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_raster_processing.zip"
  source      = data.archive_file.raster_processing_zip.output_path
  source_hash = filemd5(data.archive_file.raster_processing_zip.output_path)
}

resource "aws_ecr_repository" "viz_raster_processing_image" {
  name                 = "viz_raster_processing"
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_codebuild_project" "viz_raster_processing_lambda" {
  name          = "viz-${var.environment}-raster-processing"
  description   = "Codebuild project that builds the lambda container based on a zip file with lambda code and dockerfile. Also deploys a lambda function using the ECR image"
  build_timeout = "60"
  service_role  = var.lambda_role

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:6.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.account_id
    }
    
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.viz_raster_processing_image.name
    }
    
    environment_variable {
      name  = "IMAGE_TAG"
      value = var.ecr_repository_image_tag
    }

    environment_variable {
      name  = "LAMBDA_NAME"
      value = local.viz_raster_processing_lambda_name
    }
    
    environment_variable {
      name  = "LAMBDA_ROLE_ARN"
      value = var.lambda_role
    }

    environment_variable {
      name  = "DEPLOYMENT_BUCKET"
      value = var.deployment_bucket
    }

    environment_variable {
      name  = "OUTPUT_BUCKET"
      value = var.raster_output_bucket
    }

    environment_variable {
      name  = "OUTPUT_PREFIX"
      value = var.raster_output_prefix
    }
  }

  source {
    type            = "S3"
    location        = "${aws_s3_object.raster_processing_zip_upload.bucket}/${aws_s3_object.raster_processing_zip_upload.key}"
  }
}

resource "null_resource" "viz_raster_processing_cluster" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    source_hash = filemd5(data.archive_file.raster_processing_zip.output_path)
  }

  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${aws_codebuild_project.viz_raster_processing_lambda.name} --profile ${var.environment}"
  }
}

data "aws_lambda_function" "viz_raster_processing" {
  function_name = local.viz_raster_processing_lambda_name

  depends_on = [
    null_resource.viz_raster_processing_cluster
  ]
}

##############################
## OPTIMIZE RASTERS LAMBDA ##
##############################

data "archive_file" "optimize_rasters_zip" {
  type = "zip"
  output_path = "${path.module}/viz_optimize_rasters_${var.environment}.zip"

  dynamic "source" {
    for_each = fileset("${path.module}/viz_optimize_rasters", "*")
    content {
      content  = file("${path.module}/viz_optimize_rasters/${source.key}")
      filename = source.key
    }
  }
}

resource "aws_s3_object" "optimize_rasters_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_optimize_rasters.zip"
  source      = data.archive_file.optimize_rasters_zip.output_path
  source_hash = filemd5(data.archive_file.optimize_rasters_zip.output_path)
}

resource "aws_ecr_repository" "viz_optimize_rasters_image" {
  name                 = "viz_optimize_rasters"
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_codebuild_project" "viz_optimize_raster_lambda" {
  name          = "viz-${var.environment}-optimize-rasters"
  description   = "Codebuild project that builds the lambda container based on a zip file with lambda code and dockerfile. Also deploys a lambda function using the ECR image"
  build_timeout = "60"
  service_role  = var.lambda_role

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:6.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.account_id
    }
    
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.viz_optimize_rasters_image.name
    }
    
    environment_variable {
      name  = "IMAGE_TAG"
      value = var.ecr_repository_image_tag
    }

    environment_variable {
      name  = "LAMBDA_NAME"
      value = local.viz_optimize_rasters_lambda_name
    }
    
    environment_variable {
      name  = "LAMBDA_ROLE_ARN"
      value = var.lambda_role
    }

    environment_variable {
      name  = "DEPLOYMENT_BUCKET"
      value = var.deployment_bucket
    }
  }

  source {
    type            = "S3"
    location        = "${aws_s3_object.optimize_rasters_zip_upload.bucket}/${aws_s3_object.optimize_rasters_zip_upload.key}"
  }
}

resource "null_resource" "viz_optimize_rasters_cluster" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    source_hash = filemd5(data.archive_file.optimize_rasters_zip.output_path)
  }

  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${aws_codebuild_project.viz_optimize_raster_lambda.name} --profile ${var.environment}"
  }
}

data "aws_lambda_function" "viz_optimize_rasters" {
  function_name = local.viz_optimize_rasters_lambda_name

  depends_on = [
    null_resource.viz_optimize_rasters_cluster
  ]
}

################################
## HAND HUC PROCESSING LAMBDA ##
################################

data "archive_file" "hand_fim_processing_zip" {
  type = "zip"
  output_path = "${path.module}/viz_hand_fim_processing_${var.environment}.zip"

  dynamic "source" {
    for_each = fileset("${path.module}/viz_hand_fim_processing", "*")
    content {
      content  = file("${path.module}/viz_hand_fim_processing/${source.key}")
      filename = source.key
    }
  }
  source {
    content  = file("${path.module}/../../layers/viz_lambda_shared_funcs/python/viz_classes.py")
    filename = "viz_classes.py"
  }
}

resource "aws_s3_object" "hand_fim_processing_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_hand_fim_processing.zip"
  source      = data.archive_file.hand_fim_processing_zip.output_path
  source_hash = filemd5(data.archive_file.hand_fim_processing_zip.output_path)
}

resource "aws_ecr_repository" "viz_hand_fim_processing_image" {
  name                 = "hand_fim_processing"
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_codebuild_project" "viz_hand_fim_processing_lambda" {
  name          = "viz-${var.environment}-hand-fim-processing"
  description   = "Codebuild project that builds the lambda container based on a zip file with lambda code and dockerfile. Also deploys a lambda function using the ECR image"
  build_timeout = "60"
  service_role  = var.lambda_role

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:6.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.account_id
    }
    
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.viz_hand_fim_processing_image.name
    }
    
    environment_variable {
      name  = "IMAGE_TAG"
      value = var.ecr_repository_image_tag
    }

    environment_variable {
      name  = "LAMBDA_NAME"
      value = local.viz_hand_fim_processing_lambda_name
    }
    
    environment_variable {
      name  = "LAMBDA_ROLE_ARN"
      value = var.lambda_role
    }

    environment_variable {
      name  = "DEPLOYMENT_BUCKET"
      value = var.deployment_bucket
    }

    environment_variable {
      name  = "FIM_BUCKET"
      value = var.fim_data_bucket
    }

    environment_variable {
      name  = "FIM_PREFIX"
      value = "fim_${replace(var.fim_version, ".", "_")}"
    }

    environment_variable {
      name  = "VIZ_DB_DATABASE"
      value = var.viz_db_name
    }

    environment_variable {
      name  = "VIZ_DB_HOST"
      value = var.viz_db_host
    }

    environment_variable {
      name  = "VIZ_DB_USERNAME"
      value = jsondecode(var.viz_db_user_secret_string)["username"]
    }

    environment_variable {
      name  = "VIZ_DB_PASSWORD"
      value = jsondecode(var.viz_db_user_secret_string)["password"]
    }

    environment_variable {
      name  = "EGIS_DB_DATABASE"
      value = var.egis_db_name
    }

    environment_variable {
      name  = "EGIS_DB_HOST"
      value = var.egis_db_host
    }

    environment_variable {
      name  = "EGIS_DB_USERNAME"
      value = jsondecode(var.egis_db_user_secret_string)["username"]
    }

    environment_variable {
      name  = "EGIS_DB_PASSWORD"
      value = jsondecode(var.egis_db_user_secret_string)["password"]
    }

    environment_variable {
      name  = "SECURITY_GROUP_1"
      value = var.hand_fim_processing_sgs[0]
    }

    environment_variable {
      name  = "SUBNET_1"
      value = var.hand_fim_processing_subnets[0]
    }

    environment_variable {
      name  = "SUBNET_2"
      value = var.hand_fim_processing_subnets[1]
    }
  }

  source {
    type            = "S3"
    location        = "${aws_s3_object.hand_fim_processing_zip_upload.bucket}/${aws_s3_object.hand_fim_processing_zip_upload.key}"
  }
}

resource "null_resource" "viz_hand_fim_processing_cluster" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    source_hash = filemd5(data.archive_file.hand_fim_processing_zip.output_path)
    fim_version = var.fim_version
  }

  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${aws_codebuild_project.viz_hand_fim_processing_lambda.name} --profile ${var.environment}"
  }
}

data "aws_lambda_function" "viz_hand_fim_processing" {
  function_name = local.viz_hand_fim_processing_lambda_name

  depends_on = [
    null_resource.viz_hand_fim_processing_cluster
  ]
}


##################################
## SCHISM HUC PROCESSING LAMBDA ##
##################################

data "archive_file" "schism_processing_zip" {
  type = "zip"
  output_path = "${path.module}/viz_schism_fim_processing_${var.environment}.zip"

  dynamic "source" {
    for_each = fileset("${path.module}/viz_schism_fim_processing", "*")
    content {
      content  = file("${path.module}/viz_schism_fim_processing/${source.key}")
      filename = source.key
    }
  }
  source {
    content  = file("${path.module}/../../layers/viz_lambda_shared_funcs/python/viz_classes.py")
    filename = "viz_classes.py"
  }
}

resource "aws_s3_object" "schism_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_schism_fim_processing.zip"
  source      = data.archive_file.schism_processing_zip.output_path
  source_hash = filemd5(data.archive_file.schism_processing_zip.output_path)
}

resource "aws_ecr_repository" "viz_schism_fim_processing_image" {
  name                 = "schism_fim_processing"
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_codebuild_project" "viz_schism_fim_processing_lambda" {
  name          = "viz-${var.environment}-schism-fim-processing"
  description   = "Codebuild project that builds the lambda container based on a zip file with lambda code and dockerfile. Also deploys a lambda function using the ECR image"
  build_timeout = "60"
  service_role  = var.lambda_role

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/standard:6.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = var.account_id
    }
    
    environment_variable {
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.viz_schism_fim_processing_image.name
    }
    
    environment_variable {
      name  = "IMAGE_TAG"
      value = var.ecr_repository_image_tag
    }

    environment_variable {
      name  = "LAMBDA_NAME"
      value = local.viz_schism_fim_processing_lambda_name
    }
    
    environment_variable {
      name  = "LAMBDA_ROLE_ARN"
      value = var.lambda_role
    }

    environment_variable {
      name  = "INPUTS_BUCKET"
      value = var.deployment_bucket
    }

    environment_variable {
      name  = "INPUTS_PREFIX"
      value = "schism_fim"
    }

    environment_variable {
      name  = "MAX_VALS_BUCKET"
      value = var.max_values_bucket
    }

    environment_variable {
      name  = "OUTPUTS_BUCKET"
      value = var.raster_output_bucket
    }

    environment_variable {
      name  = "OUTPUTS_PREFIX"
      value = "processing_outputs"
    }

    environment_variable {
      name  = "VIZ_DB_DATABASE"
      value = var.viz_db_name
    }

    environment_variable {
      name  = "VIZ_DB_HOST"
      value = var.viz_db_host
    }

    environment_variable {
      name  = "VIZ_DB_USERNAME"
      value = jsondecode(var.viz_db_user_secret_string)["username"]
    }

    environment_variable {
      name  = "VIZ_DB_PASSWORD"
      value = jsondecode(var.viz_db_user_secret_string)["password"]
    }

    environment_variable {
      name  = "SECURITY_GROUP_1"
      value = var.hand_fim_processing_sgs[0]
    }

    environment_variable {
      name  = "SUBNET_1"
      value = var.hand_fim_processing_subnets[0]
    }

    environment_variable {
      name  = "SUBNET_2"
      value = var.hand_fim_processing_subnets[1]
    }
  }

  source {
    type            = "S3"
    location        = "${aws_s3_object.schism_zip_upload.bucket}/${aws_s3_object.schism_zip_upload.key}"
  }
}

resource "null_resource" "viz_schism_fim_processing_cluster" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    source_hash = filemd5(data.archive_file.schism_processing_zip.output_path)
  }

  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${aws_codebuild_project.viz_schism_fim_processing_lambda.name} --profile ${var.environment}"
  }
}

data "aws_lambda_function" "viz_schism_fim_processing" {
  function_name = local.viz_schism_fim_processing_lambda_name

  depends_on = [
    null_resource.viz_schism_fim_processing_cluster
  ]
}


output "hand_fim_processing" {
  value = data.aws_lambda_function.viz_hand_fim_processing
}

output "schism_fim_processing" {
  value = data.aws_lambda_function.viz_schism_fim_processing
}

output "optimize_rasters" {
  value = data.aws_lambda_function.viz_optimize_rasters
}

output "raster_processing" {
  value = data.aws_lambda_function.viz_raster_processing
}