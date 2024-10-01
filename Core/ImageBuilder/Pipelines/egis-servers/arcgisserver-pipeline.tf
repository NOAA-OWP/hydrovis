resource "aws_imagebuilder_image_pipeline" "arcgis_server" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.arcgisserver_recipe.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.arcgis_build_infrastructure.arn
  name                             = "arcgisserver-${local.arcgisVersionName}"
  status                           = "ENABLED"
  description                      = "Creates an ArcGIS Server v${local.arcgisVersionName} image."
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.arcgisserver-distribution.arn

  schedule {
    schedule_expression = "cron(0 5 ? * wed *)"
    # Schedule every Wed at 5 AM after Patch Tuesdays
    pipeline_execution_start_condition = "EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE"
    timezone                           = "Etc/UTC"
  }

  # Test the image after build
  image_tests_configuration {
    image_tests_enabled = true
    timeout_minutes     = 1440
  }

  tags = merge({
    "Name" = "arcgisserver-${local.arcgisVersionName}"
  }, local.shared_tags)

  depends_on = [
    aws_imagebuilder_image_recipe.arcgisserver_recipe,
    aws_imagebuilder_infrastructure_configuration.arcgis_build_infrastructure
  ]
}

resource "aws_imagebuilder_image_recipe" "arcgisserver_recipe" {
  name         = "arcgisserver-${local.arcgisVersionName}-recipe"
  parent_image = "arn:aws:imagebuilder:${var.region}:aws:image/windows-server-2022-english-full-base-x86/x.x.x"
  version      = local.image_version
  tags         = local.shared_tags

  block_device_mapping {
    device_name = "/dev/sda1"

    ebs {
      delete_on_termination = true
      volume_size           = 200
      volume_type           = "gp3"
    }
  }

  # install Amazon CloudWatch
  component {
    component_arn = data.aws_imagebuilder_component.amazon_cloudwatch_agent_windows.arn
  }

  # bootstrap for cinc
  component {
    component_arn = aws_imagebuilder_component.esri_cinc_bootstrap.arn
    parameter {
      name  = "S3Source"
      value = local.deploymentS3Source
    }
    parameter {
      name  = "WorkingFolder"
      value = local.WorkingFolder
    }
  }

  # run install with cinc
  component {
    component_arn = aws_imagebuilder_component.esri_run_cinc_client.arn
    parameter {
      name  = "WorkingFolder"
      value = local.WorkingFolder
    }
    parameter {
      name  = "CincConfig"
      value = local.arcgisServerConfig
    }
  }

  # run patching
  component {
    component_arn = aws_imagebuilder_component.esri_patching.arn
    parameter {
      name  = "WorkingFolder"
      value = local.WorkingFolder
    }
  }

  # run windows high stig
  component {
    component_arn = data.aws_imagebuilder_component.stig_build_windows_high.arn
  }

  # run additional installs
  component {
    component_arn = aws_imagebuilder_component.additional_installs.arn
  }

  # reboot
  component {
    component_arn = data.aws_imagebuilder_component.windows_reboot.arn
  }

}

resource "aws_imagebuilder_distribution_configuration" "arcgisserver-distribution" {
  name = "arcgisserver-${local.arcgisVersionName}-distribution"

  distribution {
    region = "us-east-1"
    ami_distribution_configuration {
      name                = "arcgisserver-${local.arcgisVersionName}-{{ imagebuilder:buildDate }}"
      target_account_ids  = ["226711853580"]  
      ami_tags            = merge(data.aws_default_tags.default.tags, { Name = "arcgisserver-${local.arcgisVersionName}-distribution" }, local.shared_tags)
    }
  }
}

output "arcgisserver" {
  value = aws_imagebuilder_image_pipeline.arcgis_server
}
