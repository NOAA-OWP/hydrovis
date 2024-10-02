# PLACEHOLDER FOR FUTURE MULTICLOUD SUPPORT

# There are a lot of questions that need to be answered around targetting
# existing OWP internal resources (RDBMS & Object Storage) if deploying 
# to a Cloud Service Provider other than AWS.


provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
}

resource "azurerm_resource_group" "example" {
  name     = var.resource_group_name
  location = var.location
}

