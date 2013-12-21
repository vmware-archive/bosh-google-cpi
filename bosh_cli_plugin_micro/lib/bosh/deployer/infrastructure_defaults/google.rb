# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Deployer::InfrastructureDefaults
  GOOGLE   = {
    'name' => nil,
    'logging' => {
      'level' => 'INFO'
    },
    'dir' => nil,
    'network' => {
      'type' => 'dynamic',
      'cloud_properties' => {}
    },
    'env' => {
      'bosh' => {
        'password' => nil
      }
    },
    'resources' => {
      'persistent_disk' => 4096,
      'cloud_properties' => {
        'instance_type' => 'n1-standard-2'
      }
    },
    'cloud' => {
      'plugin' => 'google',
      'properties' => {
        'google' => {
          'project' => nil,
          'client_email' => nil,
          'pkcs12_key' => nil,
          'default_zone' => 'us-central1-a',
          'access_key_id' => nil,
          'secret_access_key' => nil,
          'ssh_user' => 'vcap'
        },
        'registry' => {
          'endpoint' => 'http://admin:admin@localhost:25889',
          'user' => 'admin',
          'password' => 'admin'
        },
        'agent' => {
          'ntp' => ['169.254.169.254'],
          'blobstore' => {
            'provider' => 'local',
            'options' => {
              'blobstore_path' => '/var/vcap/micro_bosh/data/cache'
            }
          },
          'mbus' => nil
        }
      }
    },
    'apply_spec' => {
      'properties' => {},
      'agent' => {
        'blobstore' => {},
        'nats' => {}
      }
    }
  }
end
