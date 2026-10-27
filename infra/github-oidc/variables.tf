variable "region" { 
  type = string 
  default = "us-east-1"   
}

variable "github_repo" {
  type    = string
  default = "PRAISE-C24/example-voting-app"
}

variable "state_bucket" { 
  type = string 
  default = "tfstate-663001881484-us-east-1"
}