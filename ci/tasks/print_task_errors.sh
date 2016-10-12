#!/usr/bin/env bash

set -e

source /etc/profile.d/chruby.sh
chruby 2.1.2

: ${bosh_admin_password:?}
: ${bosh_director_public_ip:?}

echo 'Printing debug output of tasks in state error'

cd bosh-cpi-src-in/ci/ruby_scripts
bosh -n target ${bosh_director_public_ip}
bosh -n login admin ${bosh_admin_password}
bosh -n tasks recent --no-filter 100 | ./print_task_debug_output.sh
