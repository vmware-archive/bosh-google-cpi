# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'rake/file_utils'
require 'yaml'
require 'common/deep_copy'
require 'bosh/stemcell/google/raw_image'

module Bosh::Stemcell::Google
  class LightStemcell
    def initialize(stemcell)
      @stemcell = stemcell
    end

    def write_archive
      stemcell.extract(exclude: 'image') do |extracted_stemcell_dir|
        Dir.chdir(extracted_stemcell_dir) do
          FileUtils.touch('image', verbose: true)

          File.open('stemcell.MF', 'w') do |out|
            Psych.dump(manifest, out)
          end

          Rake::FileUtilsExt.sh("sudo tar cvzf #{path} *")
        end
      end
    end

    def path
      File.join(File.dirname(stemcell.path), "light-#{File.basename(stemcell.path)}")
    end

    private

    attr_reader :stemcell

    def manifest
      raw_image = RawImage.new(stemcell)
      public_url = raw_image.publish
      manifest = Bosh::Common::DeepCopy.copy(stemcell.manifest)
      manifest['cloud_properties']['source_url'] = public_url
      manifest
    end
  end
end
