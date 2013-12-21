#!/usr/bin/env bash
# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

set -e

base_dir=$(readlink -nf $(dirname $0)/../..)
source $base_dir/lib/prelude_apply.bash

# we have to make this script work on both debian and redhat based systems
# as it is requried for initial network configuration on AWS and OpenStack
if [ -e "$chroot/etc/network/interfaces" ]
then

cat >> $chroot/etc/network/interfaces <<EOS
auto eth0
iface eth0 inet dhcp
EOS

elif [ -e "$chroot/etc/sysconfig/network" ]
then

cat >> $chroot/etc/sysconfig/network <<EOS
NETWORKING=yes
NETWORKING_IPV6=no
HOSTNAME=localhost.localdomain
NOZEROCONF=yes
EOS

cat >> $chroot/etc/sysconfig/network-scripts/ifcfg-eth0 <<EOS
DEVICE=eth0
BOOTPROTO=dhcp
ONBOOT=on
TYPE="Ethernet"
EOS

fi

# Add Google Compute Engine Metadata endpoint to hosts file
cat >> $chroot/etc/hosts <<EOS
# Google Compute Engine Metadata endpoint
169.254.169.254 metadata.google.internal metadata

EOS
