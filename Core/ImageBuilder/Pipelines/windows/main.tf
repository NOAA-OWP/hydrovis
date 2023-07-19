variable "environment" {
  type = string
}

variable "region" {
  type = string
}

variable "artifact_bucket_name" {
  type = string
}

variable "builder_role_instance_profile_name" {
  type = string
}

variable "builder_sg_id" {
  type = string
}

variable "builder_subnet_id" {
  type = string
}

variable "ami_sharing_account_ids" {
  type = list(string)
}

variable "egis_service_account_password" {
  type = string
}


locals {
  name = "windows-server-2019-awscli-git-pgadmin-arcgis-stig"
}

resource "aws_imagebuilder_image_pipeline" "windows" {
  image_recipe_arn                 = aws_imagebuilder_image_recipe.windows.arn
  infrastructure_configuration_arn = aws_imagebuilder_infrastructure_configuration.windows.arn
  distribution_configuration_arn   = aws_imagebuilder_distribution_configuration.windows.arn 
  name                             = local.name

  schedule {
    schedule_expression = "cron(0 0 * * ? *)"
  }
}

resource "aws_imagebuilder_image_recipe" "windows" {
  name         = local.name
  parent_image = "arn:aws:imagebuilder:${var.region}:aws:image/windows-server-2019-english-full-base-x86/x.x.x"
  version      = "1.0.0"

  working_directory = "C:\\"

  block_device_mapping {
    device_name = "/dev/sda1"

    ebs {
      delete_on_termination = true
      volume_size           = 150
      volume_type           = "gp2"
    }
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/aws-cli-version-2-windows/x.x.x"
  }

  component {
    component_arn = aws_imagebuilder_component.git_install.arn
  }

  component {
    component_arn = aws_imagebuilder_component.chrome_install.arn
  }

  component {
    component_arn = aws_imagebuilder_component.pgadmin_install.arn
  }

  component {
    component_arn = aws_imagebuilder_component.arcgis_pro_install.arn
  }

  component {
    component_arn = aws_imagebuilder_component.arcgis_pro_configure.arn
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/stig-build-windows-high/x.x.x"
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/update-windows/x.x.x"
  }

  component {
    component_arn = "arn:aws:imagebuilder:${var.region}:aws:component/reboot-windows/x.x.x"
  }
}

resource "aws_imagebuilder_component" "git_install" {
  name        = "git_install"
  description = "Install Git"
  platform    = "Windows"
  version     = "1.0.0"
  
  data = yamlencode({
    schemaVersion = 1.0
    phases = [
      {
        name = "build"
        steps = [
          {
            name = "DownloadGitSetup"
            action = "WebDownload"
            onFailure = "Abort"
            inputs = [
              {
                source = "https://github.com/git-for-windows/git/releases/download/v2.41.0.windows.3/Git-2.41.0.3-64-bit.exe"
                destination = "C:\\Temp\\git_setup.exe"
              }
            ]
          },
          {
            name = "RunGitSetup"
            action = "ExecuteBinary"
            onFailure = "Abort"
            inputs = {
              path = "{{build.DownloadGitSetup.inputs[0].destination}}"
              arguments = [
                "/VERYSILENT",
                "/NORESTART"
              ]
            }
          }
        ]
      }
    ]
  })
}

resource "aws_imagebuilder_component" "chrome_install" {
  name        = "chrome_install"
  description = "Install Chrome"
  platform    = "Windows"
  version     = "1.0.0"
  
  data = yamlencode({
    schemaVersion = 1.0
    phases = [
      {
        name = "build"
        steps = [
          {
            name = "DownloadChromeSetup"
            action = "WebDownload"
            onFailure = "Abort"
            inputs = [
              {
                source = "http://dl.google.com/chrome/install/375.126/chrome_installer.exe"
                destination = "C:\\Temp\\chrome_setup.exe"
              }
            ]
          },
          {
            name = "RunChromeSetup"
            action = "ExecuteBinary"
            onFailure = "Abort"
            inputs = {
              path = "{{build.DownloadChromeSetup.inputs[0].destination}}"
              arguments = [
                "/silent",
                "/install"
              ]
            }
          }
        ]
      }
    ]
  })
}

resource "aws_imagebuilder_component" "pgadmin_install" {
  name        = "pgadmin_install"
  description = "Install pgAdmin"
  platform    = "Windows"
  version     = "1.0.0"
  
  data = yamlencode({
    schemaVersion = 1.0
    phases = [
      {
        name = "build"
        steps = [
          {
            name = "DownloadPGAdminSetup"
            action = "WebDownload"
            onFailure = "Abort"
            inputs = [
              {
                source = "https://ftp.postgresql.org/pub/pgadmin/pgadmin4/v7.4/windows/pgadmin4-7.4-x64.exe"
                destination = "C:\\Temp\\pgadmin_setup.exe"
              }
            ]
          },
          {
            name = "RunPGAdminSetup"
            action = "ExecuteBinary"
            onFailure = "Abort"
            inputs = {
              path = "{{build.DownloadPGAdminSetup.inputs[0].destination}}"
              arguments = [
                "/VERYSILENT",
                "/NORESTART",
                "/ALLUSERS"
              ]
            }
          }
        ]
      }
    ]
  })
}

resource "aws_imagebuilder_component" "arcgis_pro_install" {
  name        = "arcgis_pro_install"
  description = "Install ArcGIS Pro"
  platform    = "Windows"
  version     = "1.0.0"
  
  data = yamlencode({
    schemaVersion = 1.0
    phases = [
      {
        name = "build"
        steps = [
          {
            name = "CreateTempFolder"
            action = "CreateFolder"
            inputs = [
              {
                path: "C:\\Temp\\ArcGISPro\\Documentation\\rsrc"
              }
            ]
          },
          {
            name = "DownloadArcGISFiles"
            action = "S3Download"
            timeoutSeconds = 600
            onFailure = "Abort"
            maxAttempts = 3
            inputs = [
              {
                source = "s3://${var.artifact_bucket_name}/Software/ArcGISPro/ArcGISPro.msi"
                destination = "C:\\Temp\\ArcGISPro\\ArcGISPro.msi"
              },
              {
                source = "s3://${var.artifact_bucket_name}/Software/ArcGISPro/ArcGIS_Pro_271_176643.msp"
                destination = "C:\\Temp\\ArcGISPro\\ArcGIS_Pro_271_176643.msp"
              },
              {
                source = "s3://${var.artifact_bucket_name}/Software/ArcGISPro/ArcGISPro.cab"
                destination = "C:\\Temp\\ArcGISPro\\ArcGISPro.cab"
              },
              {
                source = "s3://${var.artifact_bucket_name}/Software/ArcGISPro/setup.ini"
                destination = "C:\\Temp\\ArcGISPro\\setup.ini"
              },
              {
                source = "s3://${var.artifact_bucket_name}/Software/ArcGISPro/Documentation/*"
                destination = "C:\\Temp\\ArcGISPro\\Documentation"
              }
            ]
          },
          {
            name = "RunArcGISInstall"
            action = "InstallMSI"
            timeoutSeconds = 5000
            onFailure = "Abort"
            inputs = {
              path       = "{{build.DownloadArcGISFiles.inputs[0].destination}}"
              logFile    = "arcgis-pro-install.log"
              reboot     = "Skip"
              properties = {
                PATCH                    = "{{build.DownloadArcGISFiles.inputs[1].destination}}"
                ADDLOCAL                 = "Pro"
                INSTALLDIR               = "\"C:\\Program Files\\ArcGIS\\Pro\""
                ALLUSERS                 = "1"
                ACCEPTEULA               = "yes"
                CHECKFORUPDATESATSTARTUP = "0"
              }
            }
          },
        ]
      }
    ]
  })
}

resource "aws_imagebuilder_component" "arcgis_pro_configure" {
  name        = "arcgis_pro_configure"
  description = "Configure ArcGIS Pro"
  platform    = "Windows"
  version     = "1.0.0"
  
  data = yamlencode({
    schemaVersion = 1.0
    phases = [
      {
        name = "build"
        steps = [
          {
            name = "ConfigureArcGISFirewallAndUser"
            action = "ExecutePowerShell"
            timeoutSeconds = 60
            onFailure = "Abort"
            maxAttempts = 3
            inputs = {
              commands = [<<-EOF
              # Firewall exception for ArcGIS Pro to License Manager
              New-NetFirewallRule -DisplayName "ArcGISPro License Manager Connection" -Direction "Outbound" -Program "C:\Program Files\ArcGIS\Pro\bin\ArcGISPro.exe" -Action "Allow"
              
              # Create user and assign to groups
              $password = '${var.egis_service_account_password}' | ConvertTo-SecureString -AsPlainText -Force
              New-LocalUser -Name arcgis -Password $password -PasswordNeverExpires -Description 'account for running all things esri'
              Add-LocalGroupMember -Group 'Administrators' -Member arcgis
              Add-LocalGroupMember -Group 'Remote Desktop Users' -Member arcgis
              EOF
              ]
            }
          },
        ]
      },
      {
        name = "validate"
        steps = [
          {
            name = "ValidateUserCredentials"
            action = "ExecutePowerShell"
            timeoutSeconds = 60
            onFailure = "Abort"
            maxAttempts = 3
            inputs = {
              commands = [<<-EOF
              # Test user credentials
              $password = '${var.egis_service_account_password}' | ConvertTo-SecureString -AsPlainText -Force
              $User = 'arcgis'
              $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $password
              Start-Process notepad.exe -Credential $credential
              Start-Sleep 10
              Get-Process Notepad | Foreach-Object { $_.CloseMainWindow() | Out-Null } | stop-process -Force
              EOF
              ]
            }
          },
        ]
      }
    ]
  })
}

data "aws_key_pair" "ec2" {
  key_name = "hv-${var.environment}-ec2-key-pair-${var.region}"
}

data "aws_default_tags" "default" {}

resource "aws_imagebuilder_infrastructure_configuration" "windows" {
  name                          = local.name
  description                   = local.name
  instance_profile_name         = var.builder_role_instance_profile_name
  instance_types                = ["t2.large", "t2.xlarge"]
  key_pair                      = data.aws_key_pair.ec2.key_name
  security_group_ids            = [var.builder_sg_id]
  subnet_id                     = var.builder_subnet_id
  terminate_instance_on_failure = true

  logging {
    s3_logs {
      s3_bucket_name = var.artifact_bucket_name
      s3_key_prefix  = "logs/${local.name}"
    }
  }

  resource_tags = { for k, v in data.aws_default_tags.default.tags: k => v if k != "CreatedBy" }
}

resource "aws_imagebuilder_distribution_configuration" "windows" {
  name = local.name

  distribution {
    ami_distribution_configuration {
      name = "${local.name}-{{ imagebuilder:buildDate }}"
      target_account_ids = var.ami_sharing_account_ids
      ami_tags = merge(data.aws_default_tags.default.tags, { Name = local.name })
    }

    region = var.region
  }
}