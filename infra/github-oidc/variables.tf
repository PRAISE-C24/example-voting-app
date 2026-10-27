variable "region" { 
  type = string 
  default = "us-east-1"   
}

variable "github_repo_sub" {
  type    = string
  default = "repo:PRAISE-C24@104138599/example-voting-app@1420352531"
}

variable "state_bucket" { 
  type = string 
  default = "tfstate-663001881484-us-east-1"
}