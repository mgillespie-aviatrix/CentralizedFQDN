# This is a terraform plan for a centralized FQDN gateway setup. 
# In this example, I build a pair of spoke/transits. One pair is named "aws_fqdn_spoke/aws_fqdn_transit". This pair includes a centralized FQDN gateway
#
# The second pair is "aws_remote_spoke/aws_remote_transit". The two transits are peered, and default routes propogate the network and cause traffic to egress via the 
# Centralized FQDN gateway.
#
# This is for demonstration purposes, so the gateways are not deployed in HA mode.
#
# Numbering scheme:
# AWS_FQDN_SPOKE - 10.51.0.0/24
# AWS_FQDN_TRANSIT - 10.50.0.0/24
#
# AWS_REMOTE_SPOKE - 10.54.0.0/24
# AWS_REMOTE_TRANSIT - 10.53.0.0/24

module "configs" {
    source = "git::https://github.com/mgillespie-aviatrix/TerraformCommon?ref=v1.0.0"
}


#Step 1 - We create the FQDN spoke and transit gateway:

module "aws_fqdn_transit_gw" {
  source                 = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version                = "2.1.4"
  cidr                   = "10.50.0.0/24"
  account                = "AWS"
  cloud                  = "AWS"
  learned_cidr_approval  = false
  local_as_number        = 65301
  region                 = "us-east-2"
  name                   = "aws-fqdntransit-gw"
  instance_size          = "c5.xlarge"
  ha_gw                  = true
  enable_transit_firenet = true
}

module "aws_fqdn_spoke_gw" {
  source     = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version    = "1.2.3"
  cloud      = "AWS"
  name       = "aws-fqdn-spoke-gw"
  region     = "us-east-2"
  cidr       = "10.51.0.0/24"
  account    = "AWS"
  attached   = true
  transit_gw = module.aws_fqdn_transit_gw.transit_gateway.gw_name
  ha_gw      = true
}

#Step 2 - We create the security group for use in the spokes

resource "aws_security_group" "spoke_vpc" {
  description = "Allow CSR traffic"
  vpc_id      = module.aws_fqdn_spoke_gw.vpc.vpc_id

  ingress {
    description = "Ingress SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${module.configs.my_ip}/32"]
  }

  ingress {
    description = "Ingress SSH RFC1918"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = module.configs.rfc1918
  }

  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["${module.configs.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "csr"
  }
}

#Step 3 - We create a public ec2 instance and a private one. For testing, we'll jump from public into private and issue curl requests

module "test_vm_public" {
  source                      = "terraform-aws-modules/ec2-instance/aws"
  version                     = "~> 3.0"
  name                        = "test-vm-public"
  associate_public_ip_address = true
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.default_ssh_key
  monitoring                  = false
  vpc_security_group_ids      = [aws_security_group.spoke_vpc.id]
  subnet_id                   = module.aws_fqdn_spoke_gw.vpc.public_subnets[0].subnet_id
  tags = {
    Name = "test-vm-public"
  }
}


module "test_vm_private" {
  source                      = "terraform-aws-modules/ec2-instance/aws"
  version                     = "~> 3.0"
  name                        = "test-vm-private"
  associate_public_ip_address = false
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.default_ssh_key
  monitoring                  = false
  vpc_security_group_ids      = [aws_security_group.spoke_vpc.id]
  subnet_id                   = module.aws_fqdn_spoke_gw.vpc.private_subnets[0].subnet_id
  tags = {
    Name = "test-vm-private"
  }
}

#Step 4 - We now create the remote spoke and transit gateway
module "aws_remote_transit_gw" {
  source                 = "terraform-aviatrix-modules/mc-transit/aviatrix"
  version                = "2.1.4"
  cidr                   = "10.53.0.0/24"
  account                = "AWS"
  cloud                  = "AWS"
  learned_cidr_approval  = false
  local_as_number        = 65302
  region                 = "us-east-2"
  name                   = "aws-remote-transit-gw"
  instance_size          = "c5.xlarge"
  ha_gw                  = true
  enable_transit_firenet = false
}

module "aws_remote_spoke_gw" {
  source     = "terraform-aviatrix-modules/mc-spoke/aviatrix"
  version    = "1.2.3"
  cloud      = "AWS"
  name       = "aws-remote-spokegw"
  region     = "us-east-2"
  cidr       = "10.54.0.0/24"
  account    = "AWS"
  attached   = true
  transit_gw = module.aws_remote_transit_gw.transit_gateway.gw_name
  ha_gw      = true
}

#Step 6 - Next, we peer the remote transit gateway with our centralized transit gateway
resource "aviatrix_transit_gateway_peering" "test_transit_gateway_peering" {
  transit_gateway_name1 = module.aws_remote_transit_gw.transit_gateway.gw_name
  transit_gateway_name2 = module.aws_fqdn_transit_gw.transit_gateway.gw_name
}


#Step 7 - We create security groups for VMs in the remote spoke VPC
resource "aws_security_group" "remote_spoke_vpc" {
  description = "Allow CSR traffic"
  vpc_id      = module.aws_remote_spoke_gw.vpc.vpc_id

  ingress {
    description = "Ingress SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${module.configs.my_ip}/32"]
  }

  ingress {
    description = "Ingress SSH RFC1918"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = module.configs.rfc1918
  }

  ingress {
    description = "ICMP"
    from_port   = -1
    to_port     = -1
    protocol    = "icmp"
    cidr_blocks = ["${module.configs.my_ip}/32"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "csr"
  }
}

#Step 8 - Next, we create the remote vms
module "test_vm_remote_public" {
  source                      = "terraform-aws-modules/ec2-instance/aws"
  version                     = "~> 3.0"
  name                        = "test-vm-remote-public"
  associate_public_ip_address = true
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.default_ssh_key
  monitoring                  = false
  vpc_security_group_ids      = [aws_security_group.remote_spoke_vpc.id]
  subnet_id                   = module.aws_remote_spoke_gw.vpc.public_subnets[0].subnet_id
  tags = {
    Name = "test-vm-remote-public"
  }
}

module "test_vm_remote_private" {
  source                      = "terraform-aws-modules/ec2-instance/aws"
  version                     = "~> 3.0"
  name                        = "test-vm-remote-private"
  associate_public_ip_address = false
  ami                         = var.ami_id
  instance_type               = var.instance_type
  key_name                    = var.default_ssh_key
  monitoring                  = false
  vpc_security_group_ids      = [aws_security_group.remote_spoke_vpc.id]
  subnet_id                   = module.aws_remote_spoke_gw.vpc.private_subnets[0].subnet_id
  tags = {
    Name = "test-vm-remote-private"
  }
}


#Step 9 - Now we create a centralized FQDN gateway

resource "aviatrix_gateway" "fqdn_gw" {
  single_az_ha          = true
  gw_name               = "AVXNVA-TRANSIT-FQDN-GW"
  vpc_id                = module.aws_fqdn_transit_gw.vpc.vpc_id
  cloud_type            = 1
  vpc_reg               = "us-east-2"
  gw_size               = "t3.small"
  account_name          = "AWS"
  subnet                = "10.50.0.0/28"
  enable_encrypt_volume = true
  single_ip_snat        = false
}

resource "aviatrix_firewall_instance_association" "firewall_instance_association_1" {
  vpc_id          = module.aws_fqdn_transit_gw.vpc.vpc_id
  firenet_gw_name = module.aws_fqdn_transit_gw.transit_gateway.gw_name
  instance_id     = "AVXNVA-TRANSIT-FQDN-GW"
  vendor_type     = "fqdn_gateway"
  attached        = true
}

resource "aviatrix_fqdn" "fqdn_1" {
  #IF you don't force this to depend upon the association, it will fail with SNAT issues.
  # The gateway will be stuck in a problem where Terraform complains about disabling SNAT
  depends_on = [
    aviatrix_firewall_instance_association.firewall_instance_association_1
  ]
  fqdn_mode    = "white"
  fqdn_enabled = true
  gw_filter_tag_list {
    gw_name = aviatrix_gateway.fqdn_gw.gw_name
  }
  fqdn_tag            = "CentralizedFQDNFiltering"
  manage_domain_names = false
}

resource "aviatrix_fqdn_tag_rule" "fqdn_tag_rule_1" {
  #This requires the DB to be created first. I'm also tagging the firewall association as a pre-req, although it
  # may technically not be. 
  depends_on = [
    aviatrix_fqdn.fqdn_1,
    aviatrix_firewall_instance_association.firewall_instance_association_1
  ]
  fqdn_tag_name = "CentralizedFQDNFiltering"
  fqdn          = "*.google.com"
  protocol      = "tcp"
  port          = "443"
}
