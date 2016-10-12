#!/usr/bin/env bash

set -e

source /etc/profile.d/chruby.sh
chruby 2.1.2

export BOSH_INIT_LOG_LEVEL=DEBUG

working_dir=$PWD
deployment_dir=$PWD/upgrade-deployment

cp ./bosh-cpi-release/*.tgz bosh-openstack-cpi.tgz
cp ./bosh-release/release.tgz bosh-release.tgz
cp ./stemcell/stemcell.tgz stemcell.tgz
cp $deployment_dir/director-manifest* .
cp -r $deployment_dir/.bosh_init $HOME/

initver=$(cat bosh-init/version)
initexe="bosh-init/bosh-init-${initver}-linux-amd64"
chmod +x ${initexe}

echo "using bosh-init CLI version..."
$initexe version

director_manifest_file=director-manifest.yml
echo "deleting existing BOSH Director VM..."
time $initexe delete ${director_manifest_file}