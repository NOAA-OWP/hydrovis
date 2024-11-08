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

variable "python_preprocessing_bucket" {
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

variable "hand_version" {
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
  type = map(string)
}

variable "nwm_dataflow_version" {
  type = string
}

locals {
  viz_optimize_rasters_lambda_name = "hv-vpp-${var.environment}-viz-optimize-rasters"
  viz_hand_fim_processing_lambda_name = "hv-vpp-${var.environment}-viz-hand-fim-processing"
  viz_schism_fim_processing_lambda_name = "hv-vpp-${var.environment}-viz-schism-fim-processing"
  viz_raster_processing_lambda_name = "hv-vpp-${var.environment}-viz-raster-processing"
}

##############################
## RASTER PROCESSING LAMBDA ##
##############################

data "archive_file" "raster_processing_zip" {
  type = "zip"
  output_path = "${path.module}/temp/viz_raster_processing_${var.environment}_${var.region}.zip"

  dynamic "source" {
    for_each = fileset("${path.module}/viz_raster_processing", "**")
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
      NWM_DATAFLOW_VERSION = var.nwm_dataflow_version
    })
    filename = "serverless.yml"
  }
}

resource "aws_s3_object" "raster_processing_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_raster_processing.zip"
  source      = data.archive_file.raster_processing_zip.output_path
  source_hash = data.archive_file.raster_processing_zip.output_md5
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
  name          = local.viz_raster_processing_lambda_name
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
    source_hash = data.archive_file.raster_processing_zip.output_md5
  }

  depends_on = [ aws_s3_object.raster_processing_zip_upload ]

  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${aws_codebuild_project.viz_raster_processing_lambda.name} --profile ${var.environment} --region ${var.region}"
  }
}

resource "time_sleep" "wait_for_viz_raster_processing_cluster" {
  triggers = {
    function_update = null_resource.viz_raster_processing_cluster.triggers.source_hash
  }
  depends_on = [null_resource.viz_raster_processing_cluster]

  create_duration = "120s"
}

data "aws_lambda_function" "viz_raster_processing" {
  function_name = aws_codebuild_project.viz_raster_processing_lambda.name

  depends_on = [
    time_sleep.wait_for_viz_raster_processing_cluster
  ]
}

##############################
## OPTIMIZE RASTERS LAMBDA ##
##############################

data "archive_file" "optimize_rasters_zip" {
  type = "zip"
  output_path = "${path.module}/temp/viz_optimize_rasters_${var.environment}_${var.region}.zip"

  dynamic "source" {
    for_each = fileset("${path.module}/viz_optimize_rasters", "**")
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
  key         = "terraform_artifacts/${path.module}/viz_optimize_rasters.zip"
  source      = data.archive_file.optimize_rasters_zip.output_path
  source_hash = data.archive_file.optimize_rasters_zip.output_md5
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
  name          = local.viz_optimize_rasters_lambda_name
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
    source_hash = data.archive_file.optimize_rasters_zip.output_md5
  }

  depends_on = [ aws_s3_object.optimize_rasters_zip_upload ]

  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${aws_codebuild_project.viz_optimize_raster_lambda.name} --profile ${var.environment} --region ${var.region}"
  }
}

resource "time_sleep" "wait_for_viz_optimize_rasters_cluster" {
  triggers = {
    function_update = null_resource.viz_optimize_rasters_cluster.triggers.source_hash
  }
  depends_on = [null_resource.viz_optimize_rasters_cluster]

  create_duration = "120s"
}

data "aws_lambda_function" "viz_optimize_rasters" {
  function_name = local.viz_optimize_rasters_lambda_name

  depends_on = [
    time_sleep.wait_for_viz_optimize_rasters_cluster
  ]
}

################################
## HAND HUC PROCESSING LAMBDA ##
################################

data "archive_file" "hand_fim_processing_zip" {
  type = "zip"
  output_path = "${path.module}/temp/viz_hand_fim_processing_${var.environment}_${var.region}.zip"

  dynamic "source" {
    for_each = fileset("${path.module}/viz_hand_fim_processing", "**")
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
      FIM_VERSION        = var.fim_version
      HAND_BUCKET        = var.fim_data_bucket
      HAND_VERSION       = var.hand_version
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
  key         = "terraform_artifacts/${path.module}/viz_hand_fim_processing.zip"
  source      = data.archive_file.hand_fim_processing_zip.output_path
  source_hash = data.archive_file.hand_fim_processing_zip.output_md5
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
  name          = local.viz_hand_fim_processing_lambda_name
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
    source_hash = data.archive_file.hand_fim_processing_zip.output_md5
    hand_version = var.hand_version
    fim_version = var.fim_version
  }

  depends_on = [ aws_s3_object.hand_fim_processing_zip_upload ]

  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${aws_codebuild_project.viz_hand_fim_processing_lambda.name} --profile ${var.environment} --region ${var.region}"
  }
}

resource "time_sleep" "wait_for_viz_hand_fim_processing_cluster" {
  triggers = {
    function_update = null_resource.viz_hand_fim_processing_cluster.triggers.source_hash
  }
  depends_on = [null_resource.viz_hand_fim_processing_cluster]

  create_duration = "120s"
}

data "aws_lambda_function" "viz_hand_fim_processing" {
  function_name = local.viz_hand_fim_processing_lambda_name

  depends_on = [
    time_sleep.wait_for_viz_hand_fim_processing_cluster
  ]
}


###########################
## SCHISM FIM PROCESSING ##
###########################

module "schism-fim" {
  source = "./viz_schism_fim_processing"
  
  environment                 = var.environment
  account_id                  = var.account_id
  region                      = var.region
  ecr_repository_image_tag    = var.ecr_repository_image_tag
  codebuild_role              = var.lambda_role
  security_groups             = var.hand_fim_processing_sgs
  subnets                     = var.hand_fim_processing_subnets
  deployment_bucket           = var.deployment_bucket
  profile_name                = var.environment
  viz_db_name                 = var.viz_db_name
  viz_db_host                 = var.viz_db_host
  viz_db_user_secret_string   = var.viz_db_user_secret_string
}

output "hand_fim_processing" {
  value = data.aws_lambda_function.viz_hand_fim_processing
}

output "schism_fim" {
  value = module.schism-fim
}

output "optimize_rasters" {
  value = data.aws_lambda_function.viz_optimize_rasters
}

output "raster_processing" {
  value = data.aws_lambda_function.viz_raster_processing
}