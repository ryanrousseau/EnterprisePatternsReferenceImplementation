terraform {
  backend "pg" {
    conn_str = "postgres://terraform:terraform@localhost:15432/serialize_and_deploy?sslmode=disable"
  }
}

terraform {
  required_providers {
    octopusdeploy = { source = "OctopusDeployLabs/octopusdeploy", version = "0.12.1" }
  }
}

variable "octopus_space_id" {
  type        = string
  nullable    = false
  sensitive   = false
  description = "The ID of the Octopus space to populate."
  default     = "Spaces-1"

  validation {
    condition     = length(var.octopus_space_id) > 7 && substr(var.octopus_space_id, 0, 7) == "Spaces-"
    error_message = "The space_id value must be a valid Space id, starting with \"Spaces-\"."
  }
}

variable "project_name" {
  type        = string
  nullable    = false
  sensitive   = false
  description = "The name of the project to attach the runbooks to."
}

variable "project_name_override" {
  type        = bool
  nullable    = false
  sensitive   = false
  default     = true
  description = "Whether the downstream project name can be customized."
}

provider "octopusdeploy" {
  address  = "http://localhost:18080"
  api_key  = "API-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
  space_id = var.octopus_space_id
}

module "octopus" {
  source                = "../octopus"
  project_name          = var.project_name
  project_name_override = var.project_name_override
}