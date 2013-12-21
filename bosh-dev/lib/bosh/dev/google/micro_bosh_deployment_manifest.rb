# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'bosh/dev/google'
require 'bosh/dev/writable_manifest'

module Bosh::Dev::Google
  class MicroBoshDeploymentManifest
    include Bosh::Dev::WritableManifest

    attr_reader :filename

    def initialize(env)
      @env = env
      @filename = 'micro_bosh.yml'
    end

    def to_h
      {
        'name' => director_name,
        'logging' => {
          'level' => 'DEBUG'
        },
        'network' => {
          'type' => 'dynamic',
          'vip' => env['BOSH_GOOGLE_MICROBOSH_IP'],
          'cloud_properties' => {
            'tags' => ['bosh']
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
          'properties' => cpi_options
        },
        'apply_spec' => {
          'properties' => {}
        }
      }
    end

    def cpi_options
      {
        'google' => {
          'project' => env['BOSH_GOOGLE_PROJECT'],
          'client_email' => env['BOSH_GOOGLE_CLIENT_EMAIL'],
          'pkcs12_key' => Base64.encode64(File.new(env['BOSH_GOOGLE_PKCS12_KEY_FILE'], 'rb').read),
          'default_zone' => env['BOSH_GOOGLE_DEFAULT_ZONE'],
          'access_key_id' => env['BOSH_GOOGLE_ACCESS_KEY_ID'],
          'secret_access_key' => env['BOSH_GOOGLE_SECRET_ACCESS_KEY'],
          'private_key' => env['BOSH_GOOGLE_PRIVATE_KEY']
        },
        'registry' => {
          'endpoint' => 'http://admin:admin@localhost:25889',
          'user' => 'admin',
          'password' => 'admin'
        }
      }
    end

    def director_name
      'microbosh-google-jenkins'
    end

    def zone
      env['BOSH_GOOGLE_DEFAULT_ZONE']
    end

    private

    attr_reader :env
  end
end
