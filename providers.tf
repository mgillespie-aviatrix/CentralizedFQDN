terraform {
  required_providers {
    aviatrix = {
      source  = "aviatrixsystems/aviatrix"
      version = "2.22.1"
    }
    aws = {
      source  = "hashicorp/aws"
      version = "4.18.0"
    }
  }
}

provider "aviatrix" {
  controller_ip = var.aviatrix_controller_ip
  username      = var.aviatrix_username
  password      = var.aviatrix_password
}

provider "aws" {
  region = "us-east-2"
  default_tags {
    tags = {
      "Automated-Shutdown-Enabled" = "true"
    }
  }
}