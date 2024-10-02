# PLACEHOLDER FOR FUTURE MULTICLOUD SUPPORT

# There are a lot of questions that need to be answered around targetting
# existing OWP internal resources (RDBMS & Object Storage) if deploying 
# to a Cloud Service Provider other than AWS.


provider "google" {
  project = var.project_id
  region  = var.region
}
