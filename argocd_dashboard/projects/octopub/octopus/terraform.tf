# Look up the "Simple" lifecycle that is expected to exist in the management space.
data "octopusdeploy_lifecycles" "lifecycle_simple" {
  ids          = null
  partial_name = "Simple"
  skip         = 0
  take         = 1
}

# Look up the "Docker" feed that is expected to exist in the management space.
data "octopusdeploy_feeds" "feed_docker" {
  feed_type    = "Docker"
  ids          = null
  partial_name = "Docker"
  skip         = 0
  take         = 1
}

# Look up the built-in feed automatically created with every space.
data "octopusdeploy_feeds" "feed_octopus_server__built_in_" {
  feed_type    = "BuiltIn"
  ids          = null
  partial_name = ""
  skip         = 0
  take         = 1
}

# Look up the "Default Worker Pool" worker pool that is exists by default in every new space.
data "octopusdeploy_worker_pools" "workerpool_default" {
  name = "Default Worker Pool"
  ids  = null
  skip = 0
  take = 1
}

# Look up the "Development" environment that is expected to exist in the management space.
data "octopusdeploy_environments" "development" {
  ids          = []
  partial_name = "Development"
  skip         = 0
  take         = 1
}

# Look up the "Test" environment that is expected to exist in the management space.
data "octopusdeploy_environments" "test" {
  ids          = []
  partial_name = "Test"
  skip         = 0
  take         = 1
}

# Look up the "Production" environment that is expected to exist in the management space.
data "octopusdeploy_environments" "production" {
  ids          = []
  partial_name = "Production"
  skip         = 0
  take         = 1
}

# Look up the "Hello World" project group that is expected to exist in the management space.
data "octopusdeploy_project_groups" "project_group_octopub" {
  ids          = null
  partial_name = "Octopub"
  skip         = 0
  take         = 1
}

resource "octopusdeploy_variable" "argocd_env_metadata" {
  owner_id    = octopusdeploy_project.project_octopub.id
  type        = "String"
  name        = "Metadata.ArgoCD.Application[argocd/octopub-frontend-development].Environment"
  value       = "Development"
  description = "This variable links this project's Development environment to the octopub-frontend-development ArgoCD application in the argocd namespace"
}

resource "octopusdeploy_variable" "argocd_version_metadata" {
  owner_id    = octopusdeploy_project.project_octopub.id
  type        = "String"
  name        = "Metadata.ArgoCD.Application[argocd/octopub-frontend-development].ImageForReleaseVersion"
  value       = "octopussamples/octopub-frontend"
  description = "This variable indicates that the octopussamples/octopub-frontend-microservice images deployed by the ArgoCD application is used to build the Octopus release numbers"
}

resource "octopusdeploy_variable" "argocd_git_url" {
  owner_id    = octopusdeploy_project.project_octopub.id
  type        = "String"
  name        = "Project.Git.Url"
  value       = "http://gitea:3000/octopuscac/argo_cd.git"
  description = "The git URL repo"
}

resource "octopusdeploy_variable" "argocd_git_username" {
  owner_id    = octopusdeploy_project.project_octopub.id
  type        = "String"
  name        = "Project.Git.Username"
  value       = "octopus"
  description = "The git username"
}

resource "octopusdeploy_variable" "argocd_git_password" {
  owner_id        = octopusdeploy_project.project_octopub.id
  type            = "Sensitive"
  name            = "Project.Git.Password"
  is_sensitive    = true
  sensitive_value = "Password01!"
  description     = "The git password"
}

resource "octopusdeploy_variable" "argocd_git_sourceitems" {
  owner_id    = octopusdeploy_project.project_octopub.id
  type        = "String"
  name        = "Project.Git.SourceItems"
  value       = "/argocd/octopub-frontend/overlays/development/frontend-versions.yaml"
  description = "The file that represents the release settings to be promoted between environments"
}

resource "octopusdeploy_variable" "argocd_git_destinationpath" {
  owner_id    = octopusdeploy_project.project_octopub.id
  type        = "String"
  name        = "Project.Git.DestinationPath"
  value       = "/argocd/octopub-frontend/overlays/#{Octopus.Environment.Name | ToLower}"
  description = "The directory that represents the release settings in the target environment"
}

# This is the Octopus project
resource "octopusdeploy_project" "project_octopub" {
  name                                 = "Octopub Frontend"
  description                          = "This project is used to manage the deployment of the Octopub Frontend via ArgoCD."
  auto_create_release                  = false
  default_guided_failure_mode          = "EnvironmentDefault"
  default_to_skip_if_already_installed = false
  discrete_channel_release             = false
  is_disabled                          = false
  is_version_controlled                = false
  lifecycle_id                         = data.octopusdeploy_lifecycles.lifecycle_simple.lifecycles[0].id
  project_group_id                     = data.octopusdeploy_project_groups.project_group_octopub.project_groups[0].id
  included_library_variable_sets       = []
  tenanted_deployment_participation    = "Untenanted"

  connectivity_policy {
    allow_deployments_to_no_targets = true
    exclude_unhealthy_targets       = false
    skip_machine_behavior           = "None"
  }
}

# This is the deployment process.
resource "octopusdeploy_deployment_process" "deployment_process_project_octopub" {
  project_id = octopusdeploy_project.project_octopub.id

  step {
    condition           = "Success"
    name                = "Tag the release"
    package_requirement = "LetOctopusDecide"
    start_trigger       = "StartAfterPrevious"

    action {
      action_type                        = "Octopus.Script"
      name                               = "Tag the release"
      condition                          = "Success"
      run_on_server                      = true
      is_disabled                        = false
      can_be_used_for_project_versioning = false
      is_required                        = false
      worker_pool_id                     = data.octopusdeploy_worker_pools.workerpool_default.worker_pools[0].id
      properties                         = {
        "Octopus.Action.RunOnServer"         = "true"
        "Octopus.Action.Script.ScriptSource" = "Inline"
        "Octopus.Action.Script.Syntax"       = "PowerShell"
        "Octopus.Action.Script.ScriptBody"   = file("${path.module}/Tag-Release.ps1")
      }
      environments          = [data.octopusdeploy_environments.development.environments[0].id]
      excluded_environments = []
      channels              = []
      tenant_tags           = []
      features              = []
    }

    properties   = {}
    target_roles = []
  }

  step {
    condition           = "Success"
    name                = "Promote the release"
    package_requirement = "LetOctopusDecide"
    start_trigger       = "StartAfterPrevious"

    action {
      action_type                        = "Octopus.Script"
      name                               = "Promote the release"
      condition                          = "Success"
      run_on_server                      = true
      is_disabled                        = false
      can_be_used_for_project_versioning = false
      is_required                        = false
      worker_pool_id                     = data.octopusdeploy_worker_pools.workerpool_default.worker_pools[0].id
      properties                         = {
        "Octopus.Action.RunOnServer"         = "true"
        "Octopus.Action.Script.ScriptSource" = "Inline"
        "Octopus.Action.Script.Syntax"       = "PowerShell"
        "Octopus.Action.Script.ScriptBody"   = file("${path.module}/Copy-Git-Files.ps1")
      }
      environments          = []
      excluded_environments = [data.octopusdeploy_environments.development.environments[0].id]
      channels              = []
      tenant_tags           = []
      features              = []
    }

    properties   = {}
    target_roles = []
  }
}