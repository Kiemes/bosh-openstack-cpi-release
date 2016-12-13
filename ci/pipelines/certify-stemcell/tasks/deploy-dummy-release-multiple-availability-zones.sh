#!/usr/bin/env bash

set -e

source bosh-cpi-src-in/ci/tasks/utils.sh

ensure_not_replace_value bosh_admin_password
ensure_not_replace_value stemcell_name
ensure_not_replace_value instance_flavor
ensure_not_replace_value api_key_left
ensure_not_replace_value auth_url_left
ensure_not_replace_value project_left
ensure_not_replace_value domain_left 
ensure_not_replace_value username_left
ensure_not_replace_value api_key_right
ensure_not_replace_value auth_url_right
ensure_not_replace_value project_right
ensure_not_replace_value domain_right 
ensure_not_replace_value username_right

metadata=terraform/metadata

export_terraform_variable "v3_e2e_default_key_name"
export_terraform_variable "director_public_ip"
export_terraform_variable "director_private_ip"
export_terraform_variable "dns"
export_terraform_variable "v3_e2e_security_group"
export_terraform_variable "v3_e2e_net_id"
export_terraform_variable "v3_e2e_net_cidr"
export_terraform_variable "v3_e2e_net_gateway"

metadata=terraform-secondary-openstack/metadata
export_terraform_variable "secondary_openstack_security_group_name"
export_terraform_variable "secondary_openstack_default_key_name"

source /etc/profile.d/chruby.sh
chruby 2.1.2

deployment_dir="${PWD}/deployment"
manifest_filename="dummy-manifest.yml"
cloud_config_filename="cloud-config.yml"
cpi_config_filename="cpi-config.yml"
dummy_release_name="dummy"
bosh_vcap_password_hash=$(ruby -e 'require "securerandom";puts ENV["bosh_admin_password"].crypt("$6$#{SecureRandom.base64(14)}")')

echo "setting up artifacts used in $manifest_filename"
mkdir -p ${deployment_dir}

echo "using bosh CLI version..."
bosh version

echo "targeting bosh director at ${director_public_ip}"
bosh -n target ${director_public_ip}
bosh login admin ${bosh_admin_password}

echo "uploading stemcell to director..."
bosh -n upload stemcell --skip-if-exists ./stemcell/stemcell.tgz

echo "creating cpi.yml"
cat > "${deployment_dir}/${cpi_config_filename}"<<EOF
cpis:
- name: openstack-left
  type: openstack
  properties:
    auth_url: ${auth_url_left}
    tenant: ${project_left}
    username: ${username_left}
    api_key: ${api_key_left}
    default_key_name: ${v3_e2e_default_key_name}
    default_security_groups: [${v3_e2e_security_group}]
- name: openstack-right
  type: openstack
  properties:
    auth_url: ${auth_url_right}
    tenant: ${project_right}
    username: ${username_right}
    api_key: ${api_key_right}
    default_key_name: ${secondary_openstack_default_key_name}
    default_security_groups: [${secondary_openstack_security_group_name}]
EOF

echo "updating cpi-config"
bosh -n update cpi-config ${deployment_dir}/${cpi_config_filename}

echo "creating cloud-config.yml"
cat > "${deployment_dir}/${cloud_config_filename}"<<EOF
azs:
- name: z1
  cpi: openstack-left
- name: z2
  cpi: openstack-right

vm_types:
- name: default
  cloud_properties:
    instance_type: ${instance_flavor}

disk_types:
- name: default
  disk_size: 2_000

networks:
- name: private
  type: dynamic
  dns: [${dns}]
  cloud_properties:
    net_id: ${v3_e2e_net_id}
    security_groups: [${v3_e2e_security_group}]

compilation:
  reuse_compilation_vms: true
  workers: 1
  network: private
  vm_type: default
EOF

echo "updating cloud config"
bosh -n update cloud-config ${deployment_dir}/${cloud_config_filename}

pushd dummy-release
  echo "creating release..."
  bosh -n create release --name ${dummy_release_name}

  echo "uploading release to director..."
  bosh -n upload release --skip-if-exists
popd

echo "creating dummy release manifest"
cat > "${deployment_dir}/${manifest_filename}"<<EOF
---
name: dummy
director_uuid: $(bosh status --uuid)

releases:
- name: ${dummy_release_name}
  version: latest

stemcells:
- alias: default
  name: ${stemcell_name}
  version: latest

instance_groups:
- name: dummy
  azs: [z1, z2]
  instances: 1
  jobs:
  - name: dummy
    release: ${dummy_release_name}
  vm_type: default
  stemcell: default
  networks:
  - name: private
    default: [dns, gateway]

update:
  canaries: 1
  canary_watch_time: 30000-240000
  update_watch_time: 30000-600000
  max_in_flight: 3
EOF

pushd ${deployment_dir}
  echo "deploying dummy release..."
  bosh deployment ${manifest_filename}
  bosh -n deploy
  if [ "${delete_deployment_when_done}" = "true" ]; then
    bosh -n delete deployment dummy
    bosh -n cleanup --all
  fi
popd
