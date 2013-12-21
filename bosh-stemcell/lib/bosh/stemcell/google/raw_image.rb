# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'cloud'
require 'bosh_google_cpi'
require 'ostruct'
require 'yaml'
require 'rake'

module Bosh::Stemcell::Google
  class RawImage
    attr_reader :stemcell

    def initialize(stemcell)
      @stemcell = stemcell
    end

    def publish
      cloud_config = OpenStruct.new(logger: Logger.new('google.log'), task_checkpoint: nil)
      Bosh::Clouds::Config.configure(cloud_config)

      cloud = Bosh::Clouds::Provider.create('google', options)

      stemcell.extract do |tmp_dir, stemcell_manifest|
        file_name = "#{File.basename(stemcell.path, '.tgz')}-raw.tar.gz"

        bucket = cloud.storage_api.directories.get(ENV['BOSH_GOOGLE_RAW_IMAGES_BUCKET'])
        object = bucket.files.create(key: file_name, body: File.open("#{tmp_dir}/image", 'r'), acl: 'public-read')

        object.public_url
      end
    end

    private

    def options
      # just fake the registry struct, as we don't use it
      {
        'google' => google,
        'registry' => {
          'endpoint' => 'http://fake.registry',
          'user' => 'fake',
          'password' => 'fake'
        }
    }
    end

    def google
      {
        'project' => ENV['BOSH_GOOGLE_PROJECT'],
        'client_email' => ENV['BOSH_GOOGLE_CLIENT_EMAIL'],
        'pkcs12_key' => Base64.encode64(File.new(ENV['BOSH_GOOGLE_PKCS12_KEY_FILE'], 'rb').read),
        'default_zone' => ENV['BOSH_GOOGLE_DEFAULT_ZONE'],
        'access_key_id' => ENV['BOSH_GOOGLE_ACCESS_KEY_ID'],
        'secret_access_key' => ENV['BOSH_GOOGLE_SECRET_ACCESS_KEY']
      }
    end
  end
end
