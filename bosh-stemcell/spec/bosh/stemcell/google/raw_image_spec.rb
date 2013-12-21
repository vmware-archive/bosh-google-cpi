# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'tempfile'
require 'bosh/stemcell/archive'
require 'bosh/stemcell/google/raw_image'

module Bosh::Stemcell::Google
  describe RawImage do
    subject(:raw_image) { RawImage.new(stemcell) }

    let(:stemcell) do
      instance_double('Bosh::Stemcell::Archive').tap do |s|
        s.stub(:extract).and_yield('/foo/bar', {
            'cloud_properties' => { 'source_url' => '' }
        })
        s.stub(:path).and_return('stemcell.tgz')
      end
    end

    let(:cpi)  do
      instance_double('Bosh::Google::Cloud', storage_api: storage_api)
    end

    let(:storage_api) { double('Fog::Storage::Google', directories: directories) }
    let(:directories) { double('Fog::Storage:Google:Directories', get: directory) }
    let(:directory) { double('Fog::Storage:Google:Directory', files: files) }
    let(:files) { double('Fog::Storage:Google:Files') }
    let(:file) { double('Fog::Storage:Google:File', public_url: 'fake-public-object-url') }

    before do
      Logger.stub(:new)
      ENV['BOSH_GOOGLE_PKCS12_KEY_FILE'] = Tempfile.new('pkcs12')
    end

    describe '#publish' do
      it 'creates a new image file and makes it public' do
        expect(File).to receive(:open).with('/foo/bar/image', 'r')
        expect(files).to receive(:create)
                         .with(key: 'stemcell-raw.tar.gz', body: nil, acl: 'public-read')
                         .and_return(file)

        Bosh::Clouds::Provider.stub(create: cpi)

        expect(raw_image.publish).to eq('fake-public-object-url')
      end
    end
  end
end
