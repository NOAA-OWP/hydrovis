resource "aws_imagebuilder_infrastructure_configuration" "arcgis_build_infrastructure" {
  description           = "Infrastructure to build ArcGIS images"
  instance_profile_name = aws_iam_instance_profile.EC2-ImageSTIG-builder.name
  # instance_profile_name         = aws_iam_instance_profile.arcgis_build_infrastructure_profile.name
  instance_types                = ["m5.xlarge"]
  resource_tags                 = var.tags
  name                          = "arcgis_build_infrastructure"
  terminate_instance_on_failure = true
  subnet_id                     = var.img_subnet
  security_group_ids            = [var.img_securitygroup]
  key_pair                      = var.aws_key_pair_name
  sns_topic_arn                 = aws_sns_topic.esri_image_builder_sns_topic.arn

  logging {
    s3_logs {
      s3_bucket_name = var.imageBuilderLogBucket
      s3_key_prefix  = "imagebuilder/logs"
    }
  }

  tags = var.tags
}
