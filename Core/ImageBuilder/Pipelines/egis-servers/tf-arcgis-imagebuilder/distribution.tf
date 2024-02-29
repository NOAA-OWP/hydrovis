data "aws_ami" "base_ami" {
  filter {
    name   = "image-id"
    values = [var.base_ami]
  }
}

resource "aws_imagebuilder_distribution_configuration" "arcgisenterprise-distribution" {
  name = "arcgisenterprise-${local.arcgisVersionName}-distribution"
  dynamic "distribution" {
    for_each = length(var.destination_aws_regions) > 0 ? var.destination_aws_regions : [data.aws_region.current.name]
    content {
      region = distribution.value
      ami_distribution_configuration {
        description        = "ArcGIS Enterprise v${var.arcgisenterprise_version} AMI."
        name               = format("%s-{{ imagebuilder:buildDate }}", "${var.ami_name_prefix}-arcgis-enterprise-${local.arcgisVersionName}")
        target_account_ids = var.destination_aws_accounts
        ami_tags = merge(var.tags,
          {
            "Name"                     = format("%s-{{ imagebuilder:buildDate }}", "${var.ami_name_prefix}-arcgis-enterprise-${local.arcgisVersionName}")
            "source_ami_id"            = data.aws_ami.base_ami.id
            "source_ami_name"          = data.aws_ami.base_ami.name
            "source_ami_creation_date" = data.aws_ami.base_ami.creation_date
            "arcgisenterprise_version" = var.arcgisenterprise_version
        })
      }
    }
  }
}

resource "aws_imagebuilder_distribution_configuration" "arcgisserver-distribution" {
  name = "arcgisserver-${local.arcgisVersionName}-distribution"
  dynamic "distribution" {
    for_each = length(var.destination_aws_regions) > 0 ? var.destination_aws_regions : [data.aws_region.current.name]
    content {
      region = distribution.value
      ami_distribution_configuration {
        description        = "ArcGIS Server v${var.arcgisenterprise_version} AMI."
        name               = format("%s-{{ imagebuilder:buildDate }}", "${var.ami_name_prefix}-arcgis-server-${local.arcgisVersionName}")
        target_account_ids = var.destination_aws_accounts
        ami_tags = merge(var.tags,
          {
            "Name"                     = format("%s-{{ imagebuilder:buildDate }}", "${var.ami_name_prefix}-arcgis-server-${local.arcgisVersionName}")
            "source_ami_id"            = data.aws_ami.base_ami.id
            "source_ami_name"          = data.aws_ami.base_ami.name
            "source_ami_creation_date" = data.aws_ami.base_ami.creation_date
            "arcgisenterprise_version" = var.arcgisenterprise_version
        })
      }
    }
  }
}

# output "ami_ids_arns_arcgis_enterprise" {
#     value = { for region in var.destination_aws_regions : region => aws_imagebuilder_image_pipeline.arcgis_enterprise.image_recipe_arn }
# }

# output "ami_ids_arns_arcgis_server" {
#     value = { for region in var.destination_aws_regions : region => aws_imagebuilder_image_pipeline.arcgis_server.image_recipe_arn }
# }

# resource "aws_ssm_parameter" "previous_arcgis_enterprise" {
#     for_each = toset(var.destination_aws_regions)

#     name            = "${var.aws_ssm_egis_amiid_store}/arcgis_enterprise/PreviousAMI_id_${each.key}"
#     description     = "SSM Parameter for the old AMI ID in ${each.key}"
#     type            = "String"
#     insecure_value  = " "

#     provisioner "local-exec" {
#         command = <<EOT
#             old_ami_id=$(aws ssm get-parameter --name "${var.aws_ssm_egis_amiid_store}/arcgis_enterprise/CurrentAMI_id_${each.key}" --query 'Parameter.Value' --output text)
#             aws ssm put-parameter --name "${var.aws_ssm_egis_amiid_store}/arcgis_enterprise/PreviousAMI_id_${each.key}" --value "$old_ami_id" --type "String" --overwrite --region ${each.value}
#         EOT
#     }
# }
