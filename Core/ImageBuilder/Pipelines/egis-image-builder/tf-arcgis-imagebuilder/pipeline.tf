resource "aws_imagebuilder_image_pipeline" "arcgis_enterprise" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.arcgisenterprise_recipe.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.arcgis_build_infrastructure.arn
  name                             = "arcgisenterprise-base-${local.arcgisVersionName}"
  status                           = "ENABLED"
  description                      = "Creates an ArcGIS Enterprise v${var.arcgisenterprise_version} image."
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.arcgisenterprise-distribution.arn

  schedule {
    schedule_expression = "cron(0 0 ? * sun)"
    # Schedule every Sunday at 12 AM
    pipeline_execution_start_condition = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
  }

  # Test the image after build
  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 360
  }

  tags = merge({
    "Name" = "arcgisenterprise-base-${local.arcgisVersionName}"
  }, var.tags)

  depends_on = [
    aws_imagebuilder_image_recipe.arcgisenterprise_recipe,
    aws_imagebuilder_infrastructure_configuration.arcgis_build_infrastructure
  ]
}

resource "aws_imagebuilder_image_pipeline" "arcgis_server" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.arcgisserver_recipe.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.arcgis_build_infrastructure.arn
  name                             = "arcgisserver-${local.arcgisVersionName}"
  status                           = "ENABLED"
  description                      = "Creates an ArcGIS Server v${var.arcgisenterprise_version} image."
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.arcgisserver-distribution.arn

  schedule {
    schedule_expression = "cron(0 5 ? * sun)"
    # Schedule every Sunday at 5 AM
    pipeline_execution_start_condition = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
  }

  # Test the image after build
  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 360
  }

  tags = merge({
    "Name" = "arcgisserver-${local.arcgisVersionName}"
  }, var.tags)

  depends_on = [
    aws_imagebuilder_image_recipe.arcgisserver_recipe,
    aws_imagebuilder_infrastructure_configuration.arcgis_build_infrastructure
  ]
}
