variable "region" {
  type    = string
  default = "us-east-1"
}

variable "project" {
  type    = string
  default = "example-voting-app"
}

variable "cluster_name" {
  type    = string
  default = "example-voting-app"
}

variable "kubernetes_version" {
  type    = string
  default = "1.36"
}

# Availability zones to use. EKS needs at least two.
variable "azs" {
  type    = list(string)
  default = ["us-east-1a", "us-east-1b", "us-east-1c"]
}

variable "node_instance_type" {
  type    = string
  default = "m7i-flex.large"
}

variable "node_count" {
  type    = number
  default = 2
}