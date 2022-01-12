variable "environment" {
  type = string
}

variable "account_id" {
  type = string
}

variable "region" {
  type = string
}

variable "example_data_source_id" {
  type = string
}


locals {
  example_variable = "foobar"
}


# Example Resource Block
resource "some_aws_terraform_resource" "example" {
  thing       = "${var.environment}_${var.account_id}_${var.region}"
  other_thing = var.example_data_source_id
}

# Example Output Block
output "example_output" {
  value = some_aws_terraform_resource.example.some_value
}
