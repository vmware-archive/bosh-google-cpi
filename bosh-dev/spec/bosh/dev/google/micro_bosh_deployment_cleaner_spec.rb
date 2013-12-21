# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'fog'
require 'fog/google/models/compute/servers'
require 'fog/google/models/compute/disks'
require 'fog/google/models/compute/operations'
require 'bosh/dev/google/micro_bosh_deployment_cleaner'
require 'bosh/dev/google/micro_bosh_deployment_manifest'

module Bosh::Dev::Google
  describe MicroBoshDeploymentCleaner do
    subject(:cleaner) { described_class.new(manifest) }

    let(:manifest) do
      double(Bosh::Dev::Google::MicroBoshDeploymentManifest,
        director_name: 'fake-director-name',
        cpi_options:   'fake-cpi-options',
        zone:          'fake-zone',
      )
    end
    let(:logger) { double(Logger, info: nil) }
    let(:retryable) { double(Bosh::Retryable) }
    let(:cloud) { double(Bosh::Google::Cloud) }
    let(:compute_api) { double(Fog::Compute::Google) }
    let(:servers_collection) { [] }

    before do
      allow(Logger).to receive(:new).and_return(logger)
      allow(Bosh::Retryable).to receive(:new).and_return(retryable)
      allow(retryable).to receive(:retryer).and_yield
      allow(Bosh::Google::Cloud).to receive(:new).and_return(cloud)
      allow(cloud).to receive(:compute_api).and_return(compute_api)
    end

    describe '#clean' do
      before do
        allow(compute_api).to receive(:servers).and_return(servers_collection)
      end

      context 'when matching servers are not found' do
        it 'finishes without waiting for anything' do
          cleaner.clean
        end
      end

      context 'when matching servers are found' do
        let(:servers_collection) { [server_with_non_matching, server_with_matching, microbosh_server] }
        let(:server_with_non_matching) {
          double(
            Fog::Compute::Google::Server,
            name: 'fake-name1',
            metadata: { 'items' => [{ 'key' => 'director', 'value' => 'non-matching-tag-value' }] },
          )
        }
        let(:server_with_matching) {
          double(
            Fog::Compute::Google::Server,
            name: 'fake-name2',
            metadata: { 'items' => [{ 'key' => 'director', 'value' => 'fake-director-name' }] },
          )
        }
        let(:microbosh_server) {
          double(
            Fog::Compute::Google::Server,
            name: 'fake-name3',
            metadata: { 'items' => [{ 'key' => 'Name', 'value' => 'fake-director-name' }] },
          )
        }

        it 'terminates servers that have specific microbosh tag name' do
          expect(cleaner).to_not receive(:clean_server).with(server_with_non_matching)
          expect(cleaner).to receive(:clean_server).with(server_with_matching)
          expect(cleaner).to receive(:clean_server).with(microbosh_server)

          cleaner.clean
        end
      end
    end

    describe '#clean_server' do
      let(:server) {
        double(
          Fog::Compute::Google::Server,
          name: 'fake-name1',
          disks: disks
        )
      }
      let(:disk) { double(Fog::Compute::Google::Disk) }
      let(:disks) { double(Fog::Compute::Google::Disks) }
      let(:operation) { double(Fog::Compute::Google::Operation) }

      before do
        allow(compute_api).to receive(:disks).and_return(disks)
      end

      context 'without any disk attached' do
        let(:disks) { [] }

        it 'should delete server' do
          expect(server).to receive(:destroy).and_return(operation)
          expect(operation).to receive(:reload).and_return(operation)
          expect(operation).to receive(:ready?).and_return(true)

          cleaner.clean_server(server)
        end
      end

      context 'with disks attached' do
        let(:disks) { [{ 'source' => 'disk1' }] }

        it 'should delete server and attached disks' do
          expect(server).to receive(:destroy).and_return(operation)
          expect(operation).to receive(:reload).and_return(operation)
          expect(operation).to receive(:ready?).and_return(true)
          expect(disks).to receive(:get).with('disk1', 'fake-zone').and_return(disk)
          expect(disk).to receive(:destroy)

          cleaner.clean_server(server)
        end
      end
    end
  end
end
