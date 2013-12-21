# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'bosh/dev/google'
require 'bosh/dev/writable_manifest'

module Bosh::Dev::Google
  class BatDeploymentManifest
    include Bosh::Dev::WritableManifest

    attr_reader :filename

    def initialize(env, director_uuid, stemcell_archive)
      @env = env
      @director_uuid = director_uuid
      @stemcell_archive = stemcell_archive
      @filename = 'bat.yml'
    end

    def to_h
      {
        'cpi' => 'google',
        'properties' => {
          'uuid' => director_uuid.value,
          'static_ip' => env['BOSH_GOOGLE_BAT_IP'],
          'pool_size' => 1,
          'stemcell' => {
            'name' => stemcell_archive.name,
            'version' => stemcell_archive.version
          },
          'instances' => 1,
          'mbus' => "nats://nats:0b450ada9f830085e2cdeff6@#{env['BOSH_GOOGLE_BAT_IP']}:4222",
          'network' => {
            'type' => 'dynamic',
            'cloud_properties' => {
              'tags' => ['bosh']
            }
          }
        }
      }
    end

    private

    attr_reader :env, :stemcell_archive, :director_uuid
  end
end
