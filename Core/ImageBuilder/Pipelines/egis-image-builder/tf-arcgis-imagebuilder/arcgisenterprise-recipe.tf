resource "aws_imagebuilder_image_recipe" "arcgisenterprise_recipe" {
  name         = "arcgisenterprise-${local.arcgisVersionName}-recipe"
  parent_image = var.base_ami
  version      = var.image_version
  tags         = var.tags

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
      value = var.deploymentS3Source
    }
    parameter {
      name  = "WorkingFolder"
      value = var.WorkingFolder
    }
  }

  # run install with cinc
  component {
    component_arn = aws_imagebuilder_component.esri_run_cinc_client.arn
    parameter {
      name  = "WorkingFolder"
      value = var.WorkingFolder
    }
    parameter {
      name  = "CincConfig"
      value = var.arcgisenterpriseConfig
    }
  }

  # run patching
  component {
    component_arn = aws_imagebuilder_component.esri_patching.arn
    parameter {
      name  = "WorkingFolder"
      value = var.WorkingFolder
    }
  }

  # run windows high stig
  component {
    component_arn = data.aws_imagebuilder_component.stig_build_windows_high.arn
  }

  # reboot
  component {
    component_arn = data.aws_imagebuilder_component.windows_reboot.arn
  }

}
