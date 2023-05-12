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

variable "default_tags" {
  type = string
}

locals {
  viz_optimize_rasters_lambda_name      = "hv_vpp_optimize_rasters_${var.environment}"
  viz_hand_fim_processing_lambda_name   = "hv_vpp_hand_fim_processing_${var.environment}"
  viz_schism_fim_processing_lambda_name = "hv_vpp_schism_fim_processing_${var.environment}"
  viz_raster_processing_lambda_name     = "hv_vpp_raster_processing_${var.environment}"
}

##############################
## RASTER PROCESSING LAMBDA ##
##############################

data "archive_file" "raster_processing_zip" {
  type        = "zip"
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

  source {
    content = templatefile("${path.module}/viz_raster_processing/serverless.yml.tmpl", {
      SERVICE_NAME       = replace(local.viz_raster_processing_lambda_name, "_", "-")
      LAMBDA_TAGS        = jsonencode(merge(var.default_tags, { Name = local.viz_raster_processing_lambda_name }))
      DEPLOYMENT_BUCKET  = var.deployment_bucket
      AWS_DEFAULT_REGION = var.region
      LAMBDA_NAME        = local.viz_raster_processing_lambda_name
      AWS_ACCOUNT_ID     = var.account_id
      IMAGE_REPO_NAME    = aws_ecr_repository.viz_raster_processing_image.name
      IMAGE_TAG          = var.ecr_repository_image_tag
      LAMBDA_ROLE_ARN    = var.lambda_role
      OUTPUT_BUCKET      = var.raster_output_bucket
      OUTPUT_PREFIX      = var.raster_output_prefix
    })
    filename = "serverless.yml"
  }
}

resource "aws_s3_object" "raster_processing_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_raster_processing.zip"
  source      = data.archive_file.raster_processing_zip.output_path
  source_hash = filemd5(data.archive_file.raster_processing_zip.output_path)
}

resource "aws_ecr_repository" "viz_raster_processing_image" {
  name                 = local.viz_raster_processing_lambda_name
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_codebuild_project" "viz_raster_processing_lambda" {
  name          = replace(local.viz_raster_processing_lambda_name, "_", "-")
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
    privileged_mode             = true

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
  }

  source {
    type     = "S3"
    location = "${aws_s3_object.raster_processing_zip_upload.bucket}/${aws_s3_object.raster_processing_zip_upload.key}"
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
  type        = "zip"
  output_path = "${path.module}/viz_optimize_rasters_${var.environment}.zip"

  dynamic "source" {
    for_each = fileset("${path.module}/viz_optimize_rasters", "*")
    content {
      content  = file("${path.module}/viz_optimize_rasters/${source.key}")
      filename = source.key
    }
  }

  source {
    content = templatefile("${path.module}/viz_optimize_rasters/serverless.yml.tmpl", {
      SERVICE_NAME       = replace(local.viz_optimize_rasters_lambda_name, "_", "-")
      LAMBDA_TAGS        = jsonencode(merge(var.default_tags, { Name = local.viz_optimize_rasters_lambda_name }))
      DEPLOYMENT_BUCKET  = var.deployment_bucket
      AWS_DEFAULT_REGION = var.region
      LAMBDA_NAME        = local.viz_optimize_rasters_lambda_name
      AWS_ACCOUNT_ID     = var.account_id
      IMAGE_REPO_NAME    = aws_ecr_repository.viz_optimize_rasters_image.name
      IMAGE_TAG          = var.ecr_repository_image_tag
      LAMBDA_ROLE_ARN    = var.lambda_role
    })
    filename = "serverless.yml"
  }
}

resource "aws_s3_object" "optimize_rasters_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_optimize_rasters.zip"
  source      = data.archive_file.optimize_rasters_zip.output_path
  source_hash = filemd5(data.archive_file.optimize_rasters_zip.output_path)
}

resource "aws_ecr_repository" "viz_optimize_rasters_image" {
  name                 = local.viz_optimize_rasters_lambda_name
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_codebuild_project" "viz_optimize_raster_lambda" {
  name          = replace(local.viz_optimize_rasters_lambda_name, "_", "-")
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
    privileged_mode             = true

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
  }

  source {
    type     = "S3"
    location = "${aws_s3_object.optimize_rasters_zip_upload.bucket}/${aws_s3_object.optimize_rasters_zip_upload.key}"
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
  type        = "zip"
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

  source {
    content = templatefile("${path.module}/viz_hand_fim_processing/serverless.yml.tmpl", {
      SERVICE_NAME       = replace(local.viz_hand_fim_processing_lambda_name, "_", "-")
      LAMBDA_TAGS        = jsonencode(merge(var.default_tags, { Name = local.viz_hand_fim_processing_lambda_name }))
      DEPLOYMENT_BUCKET  = var.deployment_bucket
      AWS_DEFAULT_REGION = var.region
      LAMBDA_NAME        = local.viz_hand_fim_processing_lambda_name
      AWS_ACCOUNT_ID     = var.account_id
      IMAGE_REPO_NAME    = aws_ecr_repository.viz_hand_fim_processing_image.name
      IMAGE_TAG          = var.ecr_repository_image_tag
      LAMBDA_ROLE_ARN    = var.lambda_role
      FIM_BUCKET         = var.fim_data_bucket
      FIM_PREFIX         = "fim_${replace(var.fim_version, ".", "_")}"
      VIZ_DB_DATABASE    = var.viz_db_name
      VIZ_DB_HOST        = var.viz_db_host
      VIZ_DB_USERNAME    = jsondecode(var.viz_db_user_secret_string)["username"]
      VIZ_DB_PASSWORD    = jsondecode(var.viz_db_user_secret_string)["password"]
      EGIS_DB_DATABASE   = var.egis_db_name
      EGIS_DB_HOST       = var.egis_db_host
      EGIS_DB_USERNAME   = jsondecode(var.egis_db_user_secret_string)["username"]
      EGIS_DB_PASSWORD   = jsondecode(var.egis_db_user_secret_string)["password"]
      SECURITY_GROUP_1   = var.hand_fim_processing_sgs[0]
      SUBNET_1           = var.hand_fim_processing_subnets[0]
      SUBNET_2           = var.hand_fim_processing_subnets[1]
    })
    filename = "serverless.yml"
  }
}

resource "aws_s3_object" "hand_fim_processing_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_hand_fim_processing.zip"
  source      = data.archive_file.hand_fim_processing_zip.output_path
  source_hash = filemd5(data.archive_file.hand_fim_processing_zip.output_path)
}

resource "aws_ecr_repository" "viz_hand_fim_processing_image" {
  name                 = local.viz_hand_fim_processing_lambda_name
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_codebuild_project" "viz_hand_fim_processing_lambda" {
  name          = replace(local.viz_hand_fim_processing_lambda_name, "_", "-")
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
    privileged_mode             = true

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
  }

  source {
    type     = "S3"
    location = "${aws_s3_object.hand_fim_processing_zip_upload.bucket}/${aws_s3_object.hand_fim_processing_zip_upload.key}"
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
  type        = "zip"
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

  source {
    content = templatefile("${path.module}/viz_schism_fim_processing/serverless.yml.tmpl", {
      SERVICE_NAME       = replace(local.viz_schism_fim_processing_lambda_name, "_", "-")
      LAMBDA_TAGS        = jsonencode(merge(var.default_tags, { Name = local.viz_schism_fim_processing_lambda_name }))
      DEPLOYMENT_BUCKET  = var.deployment_bucket
      AWS_DEFAULT_REGION = var.region
      LAMBDA_NAME        = local.viz_schism_fim_processing_lambda_name
      AWS_ACCOUNT_ID     = var.account_id
      IMAGE_REPO_NAME    = aws_ecr_repository.viz_schism_fim_processing_image.name
      IMAGE_TAG          = var.ecr_repository_image_tag
      LAMBDA_ROLE_ARN    = var.lambda_role
      MAX_VALS_BUCKET    = var.max_values_bucket
      INPUTS_BUCKET      = var.deployment_bucket
      INPUTS_PREFIX      = "schism_fim"
      OUTPUTS_BUCKET     = var.raster_output_bucket
      OUTPUTS_PREFIX     = "processing_outputs"
      VIZ_DB_DATABASE    = var.viz_db_name
      VIZ_DB_HOST        = var.viz_db_host
      VIZ_DB_PASSWORD    = jsondecode(var.viz_db_user_secret_string)["password"]
      VIZ_DB_USERNAME    = jsondecode(var.viz_db_user_secret_string)["username"]
      SECURITY_GROUP_1   = var.hand_fim_processing_sgs[0]
      SUBNET_1           = var.hand_fim_processing_subnets[0]
      SUBNET_2           = var.hand_fim_processing_subnets[1]
    })
    filename = "serverless.yml"
  }
}

resource "aws_s3_object" "schism_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "viz/viz_schism_fim_processing.zip"
  source      = data.archive_file.schism_processing_zip.output_path
  source_hash = filemd5(data.archive_file.schism_processing_zip.output_path)
}

resource "aws_ecr_repository" "viz_schism_fim_processing_image" {
  name                 = local.viz_schism_fim_processing_lambda_name
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_codebuild_project" "viz_schism_fim_processing_lambda" {
  name          = replace(local.viz_schism_fim_processing_lambda_name, "_", "-")
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
    privileged_mode             = true

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
  }

  source {
    type     = "S3"
    location = "${aws_s3_object.schism_zip_upload.bucket}/${aws_s3_object.schism_zip_upload.key}"
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