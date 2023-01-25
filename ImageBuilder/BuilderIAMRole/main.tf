variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "session_manager_logs_bucket_arn" {
  type = string
}

variable "session_manager_logs_kms_arn" {
  type = string
}

variable "rnr_bucket_arn" {
  type = string
}

variable "rnr_kms_arn" {
  type = string
}


resource "aws_iam_role" "hydrovis-image-builder" {
  name  = "hydrovis-image-builder_${var.region}"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Sid    = ""
        Principal = {
          Service = "ec2.amazonaws.com"
        }
      },
    ]
  })
}

resource "aws_iam_instance_profile" "hydrovis-image-builder" {
  name = "hydrovis-image-builder_${var.region}"
  role = aws_iam_role.hydrovis-image-builder.name
}


resource "aws_iam_role_policy" "hydrovis-image-builder-policy" {
  name   = "hydrovis-image-builder_${var.region}"
  role   = aws_iam_role.hydrovis-image-builder.id
  policy = templatefile("${path.module}/hydrovis-image-builder.json.tftpl", {
    region                          = var.region
    session_manager_logs_bucket_arn = var.session_manager_logs_bucket_arn
    session_manager_logs_kms_arn    = var.session_manager_logs_kms_arn
    rnr_bucket_arn                  = var.rnr_bucket_arn
    rnr_kms_arn                     = var.rnr_kms_arn
  })
}


resource "aws_iam_role_policy_attachment" "hydrovis-image-builder" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilderECRContainerBuilds",
    "arn:aws:iam::aws:policy/EC2InstanceProfileForImageBuilder"
  ])
  role       = aws_iam_role.hydrovis-image-builder.name
  policy_arn = each.value
}


output "role" {
  value = aws_iam_role.hydrovis-image-builder
}

output "profile" {
  value = aws_iam_instance_profile.hydrovis-image-builder
}