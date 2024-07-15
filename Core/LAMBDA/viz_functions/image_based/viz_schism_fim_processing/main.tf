variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "ecr_repository_image_tag" {
  type = string
  default = "latest"
}

variable "codebuild_role" {
  type = string
}

variable "security_groups" {
  type = list(string)
}

variable "subnets" {
  type = list(string)
}

variable "deployment_bucket" {
  type = string
}

variable "profile_name" {
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

locals {
  viz_schism_fim_resource_name = "hv-vpp-${var.environment}-viz-schism-fim-processing"
}


##################################
## SCHISM HUC PROCESSING LAMBDA ##
##################################

data "archive_file" "schism_processing_zip" {
  type = "zip"
  output_path = "${path.module}/temp/viz_schism_fim_processing_${var.environment}_${var.region}.zip"

  source {
    content  = file("${path.module}/buildspec.yml")
    filename = "buildspec.yml"
  }

  source {
    content  = file("${path.module}/Dockerfile")
    filename = "Dockerfile"
  }

  source {
    content  = file("${path.module}/process_schism_fim.py")
    filename = "process_schism_fim.py"
  }

  source {
    content  = file("${path.module}/requirements.txt")
    filename = "requirements.txt"
  }

  source {
    content  = file("${path.module}/../../../layers/viz_lambda_shared_funcs/python/viz_classes.py")
    filename = "viz_classes.py"
  }
}

resource "aws_s3_object" "schism_processing_zip_upload" {
  bucket      = var.deployment_bucket
  key         = "terraform_artifacts/${path.module}/viz_schism_fim_processing.zip"
  source      = data.archive_file.schism_processing_zip.output_path
  source_hash = data.archive_file.schism_processing_zip.output_md5
}

resource "aws_ecr_repository" "viz_schism_fim_processing_image" {
  name                 = local.viz_schism_fim_resource_name
  image_tag_mutability = "MUTABLE"

  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}

resource "aws_codebuild_project" "build_schism_fim_image" {
  name          = local.viz_schism_fim_resource_name
  description   = "Codebuild project that builds the lambda container based on a zip file with lambda code and dockerfile. Also deploys a lambda function using the ECR image"
  build_timeout = "60"
  service_role  = var.codebuild_role

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
    image                       = "aws/codebuild/amazonlinux2-aarch64-standard:3.0"
    type                        = "ARM_CONTAINER"
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
    type            = "S3"
    location        = "${aws_s3_object.schism_processing_zip_upload.bucket}/${aws_s3_object.schism_processing_zip_upload.key}"
  }
}

resource "null_resource" "viz_schism_fim_processing_cluster" {
  # Changes to any instance of the cluster requires re-provisioning
  triggers = {
    source_hash = data.archive_file.schism_processing_zip.output_md5
  }

  depends_on = [ aws_s3_object.schism_processing_zip_upload ]

  provisioner "local-exec" {
    command = "aws codebuild start-build --project-name ${aws_codebuild_project.build_schism_fim_image.name} --profile ${var.profile_name} --region ${var.region}"
  }
}

resource "time_sleep" "wait_for_viz_schism_fim_processing_cluster" {
  triggers = {
    function_update = null_resource.viz_schism_fim_processing_cluster.triggers.source_hash
  }
  depends_on = [null_resource.viz_schism_fim_processing_cluster]

  create_duration = "120s"
}

data "aws_iam_policy_document" "batch_assume_role" {
  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["batch.amazonaws.com"]
    }

    actions = ["sts:AssumeRole"]
  }
}

resource "aws_iam_role" "aws_batch_service_role" {
  name               = "aws_batch_service_role"
  assume_role_policy = data.aws_iam_policy_document.batch_assume_role.json
}

resource "aws_iam_role_policy_attachment" "aws_batch_service_role" {
  role       = aws_iam_role.aws_batch_service_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}


resource "aws_iam_role" "schism_execution" {
  name = "hv-vpp-${var.environment}-${var.region}-schism-execution"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = [
            "ecs-tasks.amazonaws.com",
            "ec2.amazonaws.com"
          ]
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "schism_execution" {
  name = "hv-vpp-${var.environment}-${var.region}-schism-execution"
  role = aws_iam_role.schism_execution.name
}

resource "aws_iam_role_policy" "schism_execution" {
  name   = "hv-vpp-${var.environment}-${var.region}-schism_execution"
  role   = aws_iam_role.schism_execution.id
  policy = file("${path.module}/schism_execution.json")
}

resource "aws_iam_role_policy_attachment" "schism_execution_AmazonEC2ContainerRegistryReadOnly" {
  role       = aws_iam_role.schism_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}
resource "aws_iam_role_policy_attachment" "schism_execution_AmazonEC2ContainerServiceforEC2Role" {
  role       = aws_iam_role.schism_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}
resource "aws_iam_role_policy_attachment" "schism_execution_AmazonECSTaskExecutionRolePolicy" {
  role       = aws_iam_role.schism_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}
resource "aws_iam_role_policy_attachment" "schism_execution_AmazonRDSFullAccess" {
  role       = aws_iam_role.schism_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonRDSFullAccess"
}
resource "aws_iam_role_policy_attachment" "schism_execution_AmazonS3FullAccess" {
  role       = aws_iam_role.schism_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3FullAccess"
}
resource "aws_iam_role_policy_attachment" "schism_execution_AWSBatchFullAccess" {
  role       = aws_iam_role.schism_execution.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBatchFullAccess"
}
resource "aws_iam_role_policy_attachment" "schism_execution_AWSBatchServiceRole" {
  role       = aws_iam_role.schism_execution.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBatchServiceRole"
}

resource "aws_batch_compute_environment" "schism_fim_compute_env" {
  compute_environment_name = "hv-vpp-${var.environment}-schism-fim-compute-env"

  compute_resources {
    instance_role = aws_iam_instance_profile.schism_execution.arn

    instance_type = [
      "c7g",
    ]

    min_vcpus = 0
    max_vcpus = 108

    security_group_ids = var.security_groups

    subnets = var.subnets

    type = "EC2"
  }

  service_role = aws_iam_role.aws_batch_service_role.arn
  type         = "MANAGED"
  depends_on   = [aws_iam_role_policy_attachment.aws_batch_service_role]  # Not sure on this...
}

resource "aws_batch_job_queue" "schism_fim_job_queue" {
  name     = "hv-vpp-${var.environment}-schism-fim-job-queue"
  state    = "ENABLED"
  priority = 1

  compute_environments = [
    aws_batch_compute_environment.schism_fim_compute_env.arn
  ]
}

resource "aws_batch_job_definition" "schism_fim_job_definition" {
  name = "hv-vpp-${var.environment}-schism-fim-job-definition"
  type = "container"
  container_properties = jsonencode({
    command = ["python3", "./process_schism_fim.py", "Ref::args_as_json"],
    image   = "${var.account_id}.dkr.ecr.${var.region}.amazonaws.com/${local.viz_schism_fim_resource_name}:${var.ecr_repository_image_tag}"

    resourceRequirements = [
      {
        type  = "VCPU"
        value = "4"
      },
      {
        type  = "MEMORY"
        value = "8000"
      }
    ]

    environment = [
      {
        name  = "INPUTS_BUCKET"
        value = var.deployment_bucket
      },
      {
        name  = "INPUTS_PREFIX"
        value = "schism_fim"
      },
      {
        name  = "VIZ_DB_DATABASE"
        value = var.viz_db_name
      },
      {
        name  = "VIZ_DB_HOST"
        value = var.viz_db_host
      },
      {
        name  = "VIZ_DB_PASSWORD"
        value = jsondecode(var.viz_db_user_secret_string)["password"]
      },
      {
        name  = "VIZ_DB_USERNAME"
        value = jsondecode(var.viz_db_user_secret_string)["username"]
      }
    ]
  })
}

output "job_definition" {
  value = aws_batch_job_definition.schism_fim_job_definition
}

output "job_queue" {
  value = aws_batch_job_queue.schism_fim_job_queue
}

output "execution_role_arn" {
  value = aws_iam_role.schism_execution.arn
}