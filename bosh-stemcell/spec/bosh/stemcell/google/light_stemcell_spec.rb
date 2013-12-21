# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'bosh/stemcell/google/light_stemcell'
require 'bosh/stemcell/archive'

module Bosh::Stemcell
  module Google
    describe LightStemcell do
      let(:stemcell) do
        Archive.new(spec_asset('fake-stemcell-google.tgz'))
      end

      subject(:light_stemcell) do
        LightStemcell.new(stemcell)
      end

      its(:path) { should eq(spec_asset('light-fake-stemcell-google.tgz')) }

      describe '#write_archive' do
        let(:raw_image) do
          instance_double('Bosh::Stemcell::Google::RawImage', publish: 'fake-raw-image-url')
        end

        let(:stemcell) do
          Archive.new(spec_asset('fake-stemcell-google.tgz'))
        end

        subject(:light_stemcell) do
          LightStemcell.new(stemcell)
        end

        before do
          RawImage.stub(:new).with(stemcell).and_return(raw_image)
          Rake::FileUtilsExt.stub(:sh)
          FileUtils.stub(:touch)
        end

        it 'creates an ami from the stemcell' do
          raw_image.should_receive(:publish)

          light_stemcell.write_archive
        end

        it 'creates a new tgz' do
          Rake::FileUtilsExt.should_receive(:sh) do |command|
            command.should match(/tar xzf #{stemcell.path} --directory .*/)
          end

          expected_tarfile = File.join(File.dirname(stemcell.path), 'light-fake-stemcell-google.tgz')

          Rake::FileUtilsExt.should_receive(:sh) do |command|
            command.should match(/sudo tar cvzf #{expected_tarfile} \*/)
          end

          light_stemcell.write_archive
        end

        it 'replaces the raw image with a blank placeholder' do
          FileUtils.should_receive(:touch).and_return do |file, options|
            expect(file).to match('image')
            expect(options).to eq(verbose: true)
          end

          light_stemcell.write_archive
        end

        it 'adds the source_url to the stemcell manifest' do
          Psych.should_receive(:dump).and_return do |stemcell_properties, out|
            expect(stemcell_properties['cloud_properties']['source_url']).to eq('fake-raw-image-url')
          end

          light_stemcell.write_archive
        end

        it 'names the stemcell manifest correctly' do
          # Example fails on linux without File.stub
          File.stub(:open).and_call_original
          File.should_receive(:open).with('stemcell.MF', 'w')

          light_stemcell.write_archive
        end

        it 'does not mutate original stemcell manifest' do
          expect {
            light_stemcell.write_archive
          }.not_to change { stemcell.manifest['cloud_properties'] }
        end
      end
    end
  end
end
