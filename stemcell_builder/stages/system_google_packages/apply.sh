#!/usr/bin/env bash
# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

# Install Google Daemon and Google Startup Scripts packages
mkdir -p $chroot/tmp
if [ -f $chroot/etc/debian_version ] # Ubuntu
then
  cp $assets_dir/google-compute-daemon_1.1.4-1_all.deb $chroot/tmp
  cp $assets_dir/google-startup-scripts_1.1.4-1_all.deb $chroot/tmp

  run_in_chroot $chroot "dpkg -i /tmp/google-compute-daemon_1.1.4-1_all.deb /tmp/google-startup-scripts_1.1.4-1_all.deb  || true"
  pkg_mgr install

  rm -f /tmp/google-compute-daemon_1.1.4-1_all.deb
  rm -f /tmp/google-startup-scripts_1.1.4-1_all.deb
elif [ -f $chroot/etc/centos-release ] # Centos
then
  cp $assets_dir/google-compute-daemon-1.1.4-1.noarch.rpm $chroot/tmp
  cp $assets_dir/google-startup-scripts-1.1.4-1.noarch.rpm $chroot/tmp

  run_in_chroot $chroot "yum -y install /tmp/google-compute-daemon-1.1.4-1.noarch.rpm /tmp/google-startup-scripts-1.1.4-1.noarch.rpm"

  rm -f /tmp/google-compute-daemon-1.1.4-1.noarch.rpm
  rm -f /tmp/google-startup-scripts-1.1.4-1.noarch.rpm
else
  echo "Unknown OS, exiting"
  exit 2
fi
