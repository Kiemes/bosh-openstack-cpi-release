provider "openstack" {
  auth_url    = "${var.auth_url}"
  user_name   = "${var.user_name}"
  password    = "${var.password}"
  tenant_name = "${var.project_name}"
  domain_name = "${var.domain_name}"
  insecure    = "${var.insecure}"
}

variable "auth_url" {
  description = "Authentication endpoint URL for OpenStack provider (only scheme+host+port, but without path!)"
}

variable "domain_name" {
  description = "OpenStack domain name"
}

variable "user_name" {
  description = "OpenStack pipeline technical user name"
}

variable "password" {
  description = "OpenStack user password"
}

variable "insecure" {
  default = "false"
  description = "SSL certificate validation"
}

variable "project_name" {
  description = "OpenStack project/tenant name"
}

variable "dns_nameservers" {
   default = ""
   description = "Comma-separated list of DNS server IPs"
}

variable "ext_net_name" {
  description = "OpenStack external network name to register floating IP"
}

variable "ext_net_id" {
  description = "OpenStack external network id to create router interface port"
}

variable "ext_net_cidr" {
  description = "OpenStack external network cidr"
}

variable "region_name" {
  description = "OpenStack region name"
}

variable "prefix" {
  description = "A prefix representing the name this script is used for, .e.g. v3-e2e"
}

variable "concourse_external_network_cidr" {
  description = "Network cidr where concourse is running in. Use external network cidr, if it runs within OpenStack"
}

variable "default_public_key" {
  description = "This is the actual public key which is uploaded"
}

variable "e2e_net_cidr" {
  description = "OpenStack e2e network cidr"
}

resource "openstack_compute_keypair_v2" "v3_e2e_default_key" {
  region     = "${var.region_name}"
  name       = "${var.prefix}-${var.project_name}"
  public_key = "${var.default_public_key}"
}

resource "openstack_networking_network_v2" "v3_e2e_net" {
  region         = "${var.region_name}"
  name           = "${var.prefix}-net"
  admin_state_up = "true"
}

resource "openstack_networking_subnet_v2" "v3_e2e_subnet" {
  region           = "${var.region_name}"
  network_id       = "${openstack_networking_network_v2.v3_e2e_net.id}"
  cidr             = "${var.e2e_net_cidr}"
  ip_version       = 4
  name             = "${var.prefix}-subnet"
  allocation_pools = {
    start = "${cidrhost(var.e2e_net_cidr, 200)}"
    end   = "${cidrhost(var.e2e_net_cidr, 254)}"
  }
  gateway_ip       = "${cidrhost(var.e2e_net_cidr, 1)}"
  enable_dhcp      = "true"
  dns_nameservers = ["${compact(split(",",var.dns_nameservers))}"]
}

resource "openstack_networking_router_v2" "e2e_router" {
  region           = "${var.region_name}"
  name             = "${var.prefix}-router"
  admin_state_up   = "true"
  external_gateway = "${var.ext_net_id}"
}

resource "openstack_networking_router_interface_v2" "v3_e2e_port" {
  region    = "${var.region_name}"
  router_id = "${openstack_networking_router_v2.e2e_router.id}"
  subnet_id = "${openstack_networking_subnet_v2.v3_e2e_subnet.id}"
}

resource "openstack_compute_floatingip_v2" "director_public_ip" {
  region = "${var.region_name}"
  pool   = "${var.ext_net_name}"
}

resource "openstack_compute_secgroup_v2" "e2e_secgroup" {
  region      = "${var.region_name}"
  name        = "${var.prefix}"
  description = "e2e security group"

  # Allow anything from own sec group (Any was not possible)

  rule {
    ip_protocol = "tcp"
    from_port   = "1"
    to_port     = "65535"
    self        = true
  }

  rule {
    ip_protocol = "udp"
    from_port   = "1"
    to_port     = "65535"
    self        = true
  }

  rule {
    ip_protocol = "icmp"
    from_port   = "-1"
    to_port     = "-1"
    self        = true
  }

  rule {
    ip_protocol = "tcp"
    from_port   = "22"
    to_port     = "22"
    cidr        = "0.0.0.0/0"
  }

  rule {
    ip_protocol = "tcp"
    from_port   = "25555"
    to_port     = "25555"
    cidr        = "0.0.0.0/0"
  }

  rule {
    ip_protocol = "tcp"
    from_port   = "6868"
    to_port     = "6868"
    cidr        = "${var.concourse_external_network_cidr}"
  }

  rule {
    ip_protocol = "tcp"
    from_port   = "1"
    to_port     = "65535"
    cidr        = "${var.ext_net_cidr}"
  }

  rule {
    ip_protocol = "udp"
    from_port   = "1"
    to_port     = "65535"
    cidr        = "${var.ext_net_cidr}"
  }
}

output "v3_e2e_security_group" {
  value = "${openstack_compute_secgroup_v2.e2e_secgroup.name}"
}

output "v3_e2e_net_id" {
  value = "${openstack_networking_network_v2.v3_e2e_net.id}"
}

output "v3_e2e_net_cidr" {
  value = "${openstack_networking_subnet_v2.v3_e2e_subnet.cidr}"
}

output "v3_e2e_net_gateway" {
  value = "${openstack_networking_subnet_v2.v3_e2e_subnet.gateway_ip}"
}

output "director_public_ip" {
  value = "${openstack_compute_floatingip_v2.director_public_ip.address}"
}

output "v3_e2e_default_key_name" {
  value = "${openstack_compute_keypair_v2.v3_e2e_default_key.name}"
}

output "e2e_router_id" {
  value = "${openstack_networking_router_v2.e2e_router.id}"
}

output "director_private_ip" {
  value = "${cidrhost(openstack_networking_subnet_v2.v3_e2e_subnet.cidr, 3)}"
}

output "dns" {
  value = "${var.dns_nameservers}"
}