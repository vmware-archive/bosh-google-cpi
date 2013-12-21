# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe ImageManager do
    let(:compute_api) { double(Fog::Compute::Google) }
    let(:storage_api) { double(Fog::Storage::Google) }
    let(:subject) { described_class.new(compute_api, storage_api) }

    let(:images) { double(Fog::Compute::Google::Images) }
    let(:image_identity) { 'image-identity' }
    let(:image_status) { :ready }
    let(:image) { double(Fog::Compute::Google::Image, identity: image_identity, status: image_status) }

    let(:operation) { double(Fog::Compute::Google::Operation) }

    before do
      allow(compute_api).to receive(:images).and_return(images)
    end

    describe '#get' do
      it 'should return an image' do
        expect(images).to receive(:get).with(image_identity).and_return(image)

        expect(subject.get(image_identity)).to eql(image)
      end

      it 'should raise a CloudError exception if image is not found' do
        expect(images).to receive(:get).with(image_identity).and_raise(Fog::Errors::NotFound)

        expect do
          subject.get(image_identity)
        end.to raise_error(Bosh::Clouds::CloudError, "Image `#{image_identity}' not found")
      end
    end

    describe '#create_from_url' do
      let(:unique_name) { SecureRandom.uuid }
      let(:image_description) { 'image-description' }
      let(:image_source_url) { 'url' }
      let(:image_params) do
        {
          name: "stemcell-#{unique_name}",
          description: image_description,
          raw_disk: image_source_url
        }
      end

      before do
        allow(subject).to receive(:generate_unique_name).and_return(unique_name)
      end

      it 'should create a image' do
        expect(images).to receive(:create).with(image_params).and_return(image)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(image)
        expect(image).to receive(:reload).and_return(image)

        expect(subject.create_from_url(image_source_url, image_description)).to eql(image)
      end
    end

    describe '#create_from_tarball' do
      let(:unique_name) { SecureRandom.uuid }
      let(:image_description) { 'image-description' }
      let(:image_path) { 'file://image_path' }
      let(:image_source_url) { 'url' }
      let(:image_params) do
        {
          name: "stemcell-#{unique_name}",
          description: image_description,
          raw_disk: image_source_url
        }
      end

      let(:directories) { double(Fog::Storage::Google::Directories) }
      let(:directory) { double(Fog::Storage::Google::Directory) }
      let(:bucket_params) do
        {
          key: "stemcell-#{unique_name}",
          acl: 'private'
        }
      end
      let(:files) { double(Fog::Storage::Google::Files) }
      let(:file) { double(Fog::Storage::Google::File) }
      let(:file_params) do
        {
          key: "stemcell-#{unique_name}.tar.gz",
          body: 'file',
          acl: 'public-read'
        }
      end

      before do
        allow(subject).to receive(:generate_unique_name).and_return(unique_name)
      end

      it 'should create a image' do
        expect(storage_api).to receive(:directories).and_return(directories)
        expect(directories).to receive(:create).with(bucket_params).and_return(directory)
        expect(directory).to receive(:files).and_return(files)
        expect(File).to receive(:open).with(image_path, 'r').and_return('file')
        expect(files).to receive(:create).with(file_params).and_return(file)
        expect(file).to receive(:public_url).and_return(image_source_url)
        expect(images).to receive(:create).with(image_params).and_return(image)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(image)
        expect(image).to receive(:reload).and_return(image)
        expect(directory).to receive(:destroy)
        expect(file).to receive(:destroy)

        expect(subject.create_from_tarball(image_path, image_description)).to eql(image)
      end
    end

    describe '#delete' do
      before do
        expect(images).to receive(:get).with(image_identity).and_return(image)
      end

      it 'should delete a image' do
        expect(image).to receive(:ready?).and_return(true)
        expect(image).to receive(:destroy).and_return(operation)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

        subject.delete(image_identity)
      end

      it 'should raise a CloudError exception if disk is not in a ready state' do
        expect(image).to receive(:ready?).and_return(false)

        expect do
          subject.delete(image_identity)
        end.to raise_error(Bosh::Clouds::CloudError,
                           "Cannot delete image `#{image_identity}', status is `#{image_status}'")
      end
    end
  end
end
