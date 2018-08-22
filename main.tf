/**
 * AWS DC/OS Master Instances
 * ============
 * This module creates typical DS/OS infrastructure in AWS.
 *
 * EXAMPLE
 * -------
 *
 *```hcl
 * module "dcos-master-instances" {
 *   source  = "terraform-dcos/masters/aws"
 *   version = "~> 0.1"
 *
 *   cluster_name = "production"
 *   ssh_public_key = "ssh-rsa ..."
 *
 *   num_masters = "3"
 *   num_private_agents = "2"
 *   num_public_agents = "1"
 * }
 *```
 */

// If admin ips is not set use our outbound ip.
data "http" "whatismyip" {
  url = "http://whatismyip.akamai.com/"
}

provider "aws" {}

// if availability zones is not set request the available in this region
data "aws_availability_zones" "available" {}

// create a ssh-key entry if ssh_public_key is set
resource "aws_key_pair" "deployer" {
  count      = "${var.ssh_public_key == "none" ? 0 : 1}"
  key_name   = "${var.cluster_name}-deployer-key"
  public_key = "${var.ssh_public_key}"
}

// Create a VPC and subnets
module "dcos-vpc" {
  source  = "dcos-terraform/vpc/aws"
  version = "~> 0.0"

  # version = "0.0.1"
  providers = {
    aws = "aws"
  }

  subnet_range       = "${var.subnet_range}"
  cluster_name       = "${var.cluster_name}"
  availability_zones = ["${coalescelist(var.availability_zones, data.aws_availability_zones.available.names)}"]
}

// Firewall. Create policies for instances and load balancers
module "dcos-security-groups" {
  source = "dcos-terraform/security-groups/aws"

  # version = "0.0.1"
  providers = {
    aws = "aws"
  }

  vpc_id       = "${module.dcos-vpc.vpc_id}"
  subnet_range = "${var.subnet_range}"
  cluster_name = "${var.cluster_name}"
  admin_ips    = ["${coalescelist(var.admin_ips, list("${data.http.whatismyip.body}/32"))}"]
}

// Permissions creates instances profiles so you could use Rexray and Kubernetes with AWS support
module "dcos-iam" {
  source  = "dcos-terraform/iam/aws"
  version = "~> 0.0"

  providers = {
    aws = "aws"
  }

  cluster_name = "${var.cluster_name}"
}

module "dcos-bootstrap-instance" {
  source  = "dcos-terraform/bootstrap/aws"
  version = "~> 0.0"

  providers = {
    aws = "aws"
  }

  cluster_name = "${var.cluster_name}"

  aws_subnet_ids         = ["${module.dcos-vpc.subnet_ids}"]
  aws_security_group_ids = ["${list(module.dcos-security-groups.internal, module.dcos-security-groups.admin)}"]
  aws_key_name           = "${var.ssh_public_key == "none" ? var.aws_key_name : element(coalescelist(aws_key_pair.deployer.*.key_name, list("")), 0)}"

  dcos_instance_os                = "${coalesce(var.bootstrap_os,var.dcos_instance_os)}"
  aws_root_volume_size            = "${var.bootstrap_root_volume_size}"
  aws_root_volume_type            = "${var.bootstrap_root_volume_type}"
  aws_instance_type               = "${var.bootstrap_instance_type}"
  aws_associate_public_ip_address = "${var.bootstrap_associate_public_ip_address}"

  tags = "${var.tags}"
}

module "dcos-master-instances" {
  source  = "dcos-terraform/masters/aws"
  version = "~> 0.0"

  providers = {
    aws = "aws"
  }

  cluster_name = "${var.cluster_name}"

  aws_subnet_ids         = ["${module.dcos-vpc.subnet_ids}"]
  aws_security_group_ids = ["${list(module.dcos-security-groups.internal, module.dcos-security-groups.admin)}"]
  aws_key_name           = "${var.ssh_public_key == "none" ? var.aws_key_name : element(coalescelist(aws_key_pair.deployer.*.key_name, list("")), 0)}"

  num_masters = "${var.num_masters}"

  dcos_instance_os                = "${coalesce(var.masters_os,var.dcos_instance_os)}"
  aws_root_volume_size            = "${var.masters_root_volume_size}"
  aws_instance_type               = "${var.masters_instance_type}"
  aws_associate_public_ip_address = "${var.masters_associate_public_ip_address}"

  tags = "${var.tags}"
}

module "dcos-privateagent-instances" {
  source  = "dcos-terraform/private-agents/aws"
  version = "~> 0.0"

  providers = {
    aws = "aws"
  }

  cluster_name = "${var.cluster_name}"

  aws_subnet_ids         = ["${module.dcos-vpc.subnet_ids}"]
  aws_security_group_ids = ["${list(module.dcos-security-groups.internal, module.dcos-security-groups.admin)}"]
  aws_key_name           = "${var.ssh_public_key == "none" ? var.aws_key_name : element(coalescelist(aws_key_pair.deployer.*.key_name, list("")), 0)}"

  num_private_agents = "${var.num_private_agents}"

  dcos_instance_os                = "${coalesce(var.private_agents_os,var.dcos_instance_os)}"
  aws_root_volume_size            = "${var.private_agents_root_volume_size}"
  aws_root_volume_type            = "${var.private_agents_root_volume_type}"
  aws_instance_type               = "${var.private_agents_instance_type}"
  aws_associate_public_ip_address = "${var.private_agents_associate_public_ip_address}"

  tags = "${var.tags}"
}

// DC/OS tested OSes provides sample AMIs and user-data
module "dcos-publicagent-instances" {
  source  = "dcos-terraform/public-agents/aws"
  version = "~> 0.0"

  providers = {
    aws = "aws"
  }

  cluster_name = "${var.cluster_name}"

  aws_subnet_ids         = ["${module.dcos-vpc.subnet_ids}"]
  aws_security_group_ids = ["${list(module.dcos-security-groups.internal, module.dcos-security-groups.admin)}"]
  tags                   = "${var.tags}"
  aws_key_name           = "${var.ssh_public_key == "none" ? var.aws_key_name : element(coalescelist(aws_key_pair.deployer.*.key_name, list("")), 0)}"

  num_public_agents = "${var.num_public_agents}"

  dcos_instance_os                = "${coalesce(var.public_agents_os,var.dcos_instance_os)}"
  aws_root_volume_size            = "${var.public_agents_root_volume_size}"
  aws_root_volume_type            = "${var.public_agents_root_volume_type}"
  aws_instance_type               = "${var.public_agents_instance_type}"
  aws_associate_public_ip_address = "${var.public_agents_associate_public_ip_address}"

  tags = "${var.tags}"
}

// Load balancers is providing two load balancers. One for accessing the DC/OS masters and a secondone balancing over public agents.
module "dcos-elb" {
  source  = "dcos-terraform/elb-dcos/aws"
  version = "~> 0.0"

  providers = {
    aws = "aws"
  }

  cluster_name = "${var.cluster_name}"
  subnet_ids   = ["${module.dcos-vpc.subnet_ids}"]

  security_groups_masters          = ["${list(module.dcos-security-groups.admin,module.dcos-security-groups.internal)}"]
  security_groups_masters_internal = ["${list(module.dcos-security-groups.internal)}"]
  security_groups_public_agents    = ["${list(module.dcos-security-groups.admin,module.dcos-security-groups.internal)}"]
  master_instances                 = ["${module.dcos-master-instances.instances}"]
  public_agent_instances           = ["${module.dcos-publicagent-instances.instances}"]

  tags = "${var.tags}"
}
