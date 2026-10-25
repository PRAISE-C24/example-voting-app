provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = var.project
      ManagedBy = "terraform"
    }
  }
}

# The default VPC and its default subnets (one per AZ)
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
  filter {
    name   = "default-for-az"
    values = ["true"]
  }
  filter {
    name   = "availability-zone"
    values = var.azs
  }
}

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.29.0" # check the registry for the newest 21.x and pin that

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  vpc_id     = data.aws_vpc.default.id
  subnet_ids = data.aws_subnets.default.ids

  endpoint_public_access = true

  # Gives the identity running Terraform admin rights inside the cluster
  enable_cluster_creator_admin_permissions = true

  # Keep control-plane log storage small
  cloudwatch_log_group_retention_in_days = 7

  addons = {
    coredns                = {}
    eks-pod-identity-agent = { before_compute = true }
    kube-proxy             = {}
    vpc-cni                = { before_compute = true }
  }

  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = [var.node_instance_type]
      min_size       = var.node_count
      max_size       = var.node_count
      desired_size   = var.node_count
    }
  }
}