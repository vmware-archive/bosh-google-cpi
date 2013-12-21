# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe DiskSnapshotManager do
    let(:compute_api) { double(Fog::Compute::Google) }
    let(:subject) { described_class.new(compute_api) }

    let(:snapshots) { double(Fog::Compute::Google::Snapshots) }
    let(:snapshot_identity) { 'snapshot-identity' }
    let(:snapshot_status) { :ready }
    let(:snapshot) do
      double(Fog::Compute::Google::Snapshot, identity: snapshot_identity, status: snapshot_status)
    end

    let(:operation) { double(Fog::Compute::Google::Operation) }

    before do
      allow(compute_api).to receive(:snapshots).and_return(snapshots)
    end

    describe '#get' do
      it 'should return a disk snapshot' do
        expect(snapshots).to receive(:get).with(snapshot_identity).and_return(snapshot)

        expect(subject.get(snapshot_identity)).to eql(snapshot)
      end

      it 'should raise a CloudError exception if disk snapshot is not found' do
        expect(snapshots).to receive(:get).with(snapshot_identity).and_return(nil)

        expect do
          subject.get(snapshot_identity)
        end.to raise_error(Bosh::Clouds::CloudError, "Disk snapshot `#{snapshot_identity}' not found")
      end
    end

    describe '#create' do
      let(:unique_name) { SecureRandom.uuid }
      let(:name) { "snapshot-#{unique_name}" }
      let(:deployment) { 'deployment' }
      let(:job) { 'job' }
      let(:index) { 'index' }
      let(:metadata) do
        {
          deployment: deployment,
          job: job,
          index: index
        }
      end
      let(:description) { "#{deployment}/#{job}/#{index}" }

      let(:disk_identity) { 'disk-identity' }
      let(:disk) { double(Fog::Compute::Google::Disk, identity: disk_identity) }

      before do
        allow(subject).to receive(:generate_unique_name).and_return(unique_name)
      end

      it 'should create a disk snapshot' do
        expect(disk).to receive(:create_snapshot).with(name, description).and_return(snapshot)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(snapshot)
        expect(snapshot).to receive(:reload).and_return(snapshot)

        expect(subject.create(disk, metadata)).to eql(snapshot)
      end
    end

    describe '#delete' do
      before do
        expect(snapshots).to receive(:get).with(snapshot_identity).and_return(snapshot)
      end

      it 'should delete a disk snapshot' do
        expect(snapshot).to receive(:ready?).and_return(true)
        expect(snapshot).to receive(:destroy).and_return(operation)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

        subject.delete(snapshot_identity)
      end

      it 'should raise a CloudError exception if disk snapshot is not in a ready state' do
        expect(snapshot).to receive(:ready?).and_return(false)

        expect do
          subject.delete(snapshot_identity)
        end.to raise_error(Bosh::Clouds::CloudError,
                           "Cannot delete disk snapshot `#{snapshot_identity}', status is `#{snapshot_status}'")
      end
    end
  end
end
