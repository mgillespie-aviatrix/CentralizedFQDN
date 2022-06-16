variable "aviatrix_controller_ip" {
  description = "The Aviatrix Controller IP"
  type        = string
}

variable "aviatrix_username" {
  description = "Username for Avaitrix Controller"
  type        = string
}

variable "aviatrix_password" {
  description = "Aviatrix Controller Password"
  type        = string
}

variable "ami_id" {
  type        = string
  description = "AMI ID to use"
  default     = "ami-0fa49cc9dc8d62c84"
}

variable "default_ssh_key" {
  type        = string
  description = "The default SSH key to use."
  default     = "AWSVMKey"
}
variable "instance_type" {
  type        = string
  description = "Type of instance to created"
  default     = "t2.micro"

}