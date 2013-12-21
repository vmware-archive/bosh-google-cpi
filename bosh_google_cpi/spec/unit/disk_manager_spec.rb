# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe DiskManager do
    let(:compute_api) { double(Fog::Compute::Google) }
    let(:subject) { described_class.new(compute_api) }

    let(:disks) { double(Fog::Compute::Google::Disks) }
    let(:disk_identity) { 'disk-identity' }
    let(:disk_status) { :ready }
    let(:disk) { double(Fog::Compute::Google::Disk, identity: disk_identity, status: disk_status) }

    let(:zone) { 'zone' }

    let(:operation) { double(Fog::Compute::Google::Operation) }

    before do
      allow(compute_api).to receive(:disks).and_return(disks)
    end

    describe '#get' do
      it 'should return a disk' do
        expect(disks).to receive(:get).with(disk_identity).and_return(disk)

        expect(subject.get(disk_identity)).to eql(disk)
      end

      it 'should raise a DiskNotFound exception if disk is not found' do
        expect(disks).to receive(:get).with(disk_identity).and_return(nil)

        expect do
          subject.get(disk_identity)
        end.to raise_error(Bosh::Clouds::DiskNotFound)
      end
    end

    describe '#create_blank' do
      let(:unique_name) { SecureRandom.uuid }
      let(:disk_size) { 1024 }
      let(:disk_params) do
        {
          name: "disk-#{unique_name}",
          zone: zone,
          description: 'Disk managed by BOSH',
          size_gb: disk_size / 1024
        }
      end

      before do
        allow(subject).to receive(:generate_unique_name).and_return(unique_name)
      end

      it 'should create a disk' do
        expect(disks).to receive(:create).with(disk_params).and_return(disk)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(disk)
        expect(disk).to receive(:reload).and_return(disk)

        expect(subject.create_blank(disk_size, zone)).to eql(disk)
      end

      context 'when disk size is not an Integer' do
        let(:disk_size) { 'size' }

        it 'should raise a CloudError exception' do
          expect do
            subject.create_blank(disk_size, zone)
          end.to raise_error(Bosh::Clouds::CloudError, 'Disk size needs to be an Integer')
        end
      end

      context 'when disk size is lesser than 1 GiB' do
        let(:disk_size) { 0 }

        it 'should raise a CloudError exception' do
          expect do
            subject.create_blank(disk_size, zone)
          end.to raise_error(Bosh::Clouds::CloudError, 'Minimum disk size is 1 GiB and you set 0 GiB')
        end
      end

      context 'when disk size is greater than 10 TiB' do
        let(:disk_size) { 1024 * 100_000 }

        it 'should raise a CloudError exception' do
          expect do
            subject.create_blank(disk_size, zone)
          end.to raise_error(Bosh::Clouds::CloudError, 'Maximum disk size is 10 TiB and you set 100000 GiB')
        end
      end
    end

    describe '#create_from_image' do
      let(:unique_name) { SecureRandom.uuid }
      let(:image_identity) { 'image-identity' }
      let(:image_link) { 'image-self-link' }
      let(:image) { double(Fog::Compute::Google::Image, identity: image_identity, self_link: image_link) }
      let(:disk_params) do
        {
          name: "disk-#{unique_name}",
          zone: zone,
          description: 'Disk managed by BOSH',
          source_image: image_link
        }
      end

      before do
        allow(subject).to receive(:generate_unique_name).and_return(unique_name)
      end

      it 'should create a disk' do
        expect(disks).to receive(:create).with(disk_params).and_return(disk)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(disk)
        expect(disk).to receive(:reload).and_return(disk)

        expect(subject.create_from_image(image, zone)).to eql(disk)
      end
    end

    describe '#delete' do
      before do
        expect(disks).to receive(:get).with(disk_identity).and_return(disk)
      end

      it 'should delete a disk' do
        expect(disk).to receive(:ready?).and_return(true)
        expect(disk).to receive(:destroy).and_return(operation)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

        subject.delete(disk_identity)
      end

      it 'should raise a CloudError exception if disk is not in a ready state' do
        expect(disk).to receive(:ready?).and_return(false)

        expect do
          subject.delete(disk_identity)
        end.to raise_error(Bosh::Clouds::CloudError,
                           "Cannot delete disk `#{disk_identity}', status is `#{disk_status}'")
      end
    end
  end
end
