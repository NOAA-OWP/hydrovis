# run cinc-client bootstrap
resource "aws_imagebuilder_component" "esri_cinc_bootstrap" {
  name        = "arcgisenteprise-esri-cinc-bootstrap"
  description = "Installs Cinc and Esri Cookbooks"
  platform    = "Windows"
  data        = file("${path.module}/scripts/esri_cinc_bootstrap.yml")
  version     = local.image_version
  tags        = local.shared_tags
}

# run cinc-client
resource "aws_imagebuilder_component" "esri_run_cinc_client" {
  name        = "arcgisenteprise-esri-run-cinc-client"
  platform    = "Windows"
  description = "Runs Cinc-Client and Esri Configurations"
  data        = file("${path.module}/scripts/esri_run_cinc_client.yml")
  version     = local.image_version
  tags        = local.shared_tags
}

# patching
resource "aws_imagebuilder_component" "esri_patching" {
  name        = "arcgisenteprise-esri-patching"
  description = "Installs Esri Patches"
  platform    = "Windows"
  data        = file("${path.module}/scripts/esri_patching.yml")
  version     = local.image_version
  tags        = local.shared_tags
}

### Amazon Provided Components
data "aws_imagebuilder_component" "stig_build_windows_high" {
  arn = "arn:aws:imagebuilder:${var.region}:aws:component/stig-build-windows-high/x.x.x"
}

data "aws_imagebuilder_component" "amazon_cloudwatch_agent_windows" {
  arn = "arn:aws:imagebuilder:${var.region}:aws:component/amazon-cloudwatch-agent-windows/x.x.x"
}

# additional installs
resource "aws_imagebuilder_component" "additional_installs" {
  name        = "server-additional-installs"
  description = "Install additional software that is needed"
  platform    = "Windows"
  data        = file("${path.module}/scripts/additional_installs.yml")
  version     = local.image_version
  tags        = local.shared_tags
}

data "aws_imagebuilder_component" "windows_reboot" {
  arn = "arn:aws:imagebuilder:${var.region}:aws:component/reboot-windows/x.x.x"
}
