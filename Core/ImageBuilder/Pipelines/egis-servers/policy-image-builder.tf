data "aws_iam_policy_document" "EC2-ImageSTIG-builder" {
  statement {
    effect = "Allow"
    actions = [
      "ssm:DescribeAssociation",
      "ssm:GetDeployablePatchSnapshotForInstance",
      "ssm:GetDocument",
      "ssm:DescribeDocument",
      "ssm:GetManifest",
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:ListAssociations",
      "ssm:ListInstanceAssociations",
      "ssm:PutInventory",
      "ssm:PutComplianceItems",
      "ssm:PutConfigurePackageResult",
      "ssm:UpdateAssociationStatus",
      "ssm:UpdateInstanceAssociationStatus",
      "ssm:UpdateInstanceInformation",
      "ssmmessages:CreateControlChannel",
      "ssmmessages:CreateDataChannel",
      "ssmmessages:OpenControlChannel",
      "ssmmessages:OpenDataChannel",
      "ec2messages:AcknowledgeMessage",
      "ec2messages:DeleteMessage",
      "ec2messages:FailMessage",
      "ec2messages:GetEndpoint",
      "ec2messages:GetMessages",
      "ec2messages:SendReply",
      "imagebuilder:GetComponent",
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:List",
      "s3:GetObject"
    ]
    resources = ["*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject"
    ]
    resources = [
      "arn:aws:s3:::${local.imageBuilderLogBucket}/imagebuilder/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "logs:CreateLogStream",
      "logs:CreateLogGroup",
      "logs:PutLogEvents"
    ]
    resources = [
      "arn:aws:logs:*:*:log-group:/aws/imagebuilder/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetObject"
    ]
    resources = [
      "arn:aws:s3:::aws-ssm-us-east-1/*",
      "arn:aws:s3:::aws-windows-downloads-us-east-1/*",
      "arn:aws:s3:::amazon-ssm-us-east-1/*",
      "arn:aws:s3:::amazon-ssm-packages-us-east-1/*",
      "arn:aws:s3:::us-east-1-birdwatcher-prod/*",
      "arn:aws:s3:::aws-ssm-distributor-file-us-east-1/*",
      "arn:aws:s3:::aws-ssm-document-attachments-us-east-1/*",
      "arn:aws:s3:::patch-baseline-snapshot-us-east-1/*",
      "arn:aws:s3:::hydrovis-11-3-deployment/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:PutObjectTagging",
      "s3:DeleteObject",
      "s3:PutObjectAcl"
    ]
    resources = [
      "arn:aws:s3:::hydroviz-imagebuilder-artifacts/*",
      "arn:aws:s3:::hydrovis-dev-rnr-us-east-1/*",
      "arn:aws:s3:::hydrovis-11-3-deployment/*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:ListBucket"
    ]
    resources = [
      "arn:aws:s3:::hydrovis-11-3-deployment"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "s3:GetEncryptionConfiguration"
    ]
    resources = [
      "arn:aws:s3:::*"
    ]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt"
    ]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "kms:EncryptionContextKeys"

      values = [
        "aws:imagebuilder:arn"
      ]
    }

    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "aws:CalledVia"

      values = [
        "imagebuilder.amazonaws.com"
      ]
    }
  }
}

resource "aws_iam_role" "EC2-ImageSTIG-builder" {
  name        = local.aws_role
  description = "EC2-ImageSTIG-builder role"

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

resource "aws_iam_instance_profile" "EC2-ImageSTIG-builder" {
  name = local.aws_role
  role = aws_iam_role.EC2-ImageSTIG-builder.name
}

resource "aws_iam_policy" "EC2-ImageSTIG-builder" {
  name        = local.aws_role
  description = "EC2-ImageSTIG-builder policy"
  path        = "/"
  policy      = data.aws_iam_policy_document.EC2-ImageSTIG-builder.json
}

resource "aws_iam_role_policy_attachment" "EC2-ImageSTIG-builder" {
  role       = aws_iam_role.EC2-ImageSTIG-builder.name
  policy_arn = aws_iam_policy.EC2-ImageSTIG-builder.arn
}
