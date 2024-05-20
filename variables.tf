variable "location" {
  default = "germanywestcentral"
  type    = string
}

variable "resource_group_name" {
  default = "atlantis-rg"
  type    = string
}

variable "create_resource_group" {
  default = true
  type    = bool
}

variable "gh_app_id" {
  type = string
}

variable "gh_app_key" {
  type = string
}
variable "gh_webhook_secret" {
  type = string
}

variable "domain_name" {
  type = string
}

variable "repo_whitelist" {
  type = string
}
