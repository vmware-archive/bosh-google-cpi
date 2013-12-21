# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'bosh/deployer/instance_manager/google'
require 'cloud/google'
require 'fog/google/models/compute/disks'
require 'fog/google/models/compute/servers'

module Bosh::Deployer
  describe InstanceManager::Google do
    let(:subject)  { described_class.new(instance_manager, config, logger) }
    let(:instance_manager) { double(Bosh::Deployer::InstanceManager) }
    let(:config) { double(Bosh::Deployer::Config, cloud_options: cloud_options) }
    let(:logger) { double(Logger, info: nil) }
    let(:registry) { double(Bosh::Deployer::Registry) }
    let(:ssh_server) { double(Bosh::Deployer::SshServer) }
    let(:remote_tunnel) { double(Bosh::Deployer::RemoteTunnel) }

    let(:google_options) {
      {
        'project' => 'cloud-project',
        'client_email' => 'email@developer.gserviceaccount.com',
        'pkcs12_key' => 'pkcs12-key',
        'default_zone' => 'zone',
        'access_key_id' => 'access_key_id',
        'secret_access_key' => 'secret_access_key',
        'private_key' => 'spec/assets/fake-private.key'
      }
    }
    let(:registry_options) {
      {
        'endpoint' => "http://admin:admin@localhost:#{registry_port}",
        'user' => 'admin',
        'password' => 'admin'
      }
    }
    let(:cloud_options) {
      {
        'plugin' => 'google',
        'properties' => {
          'google' => google_options,
          'registry' => registry_options
        }
      }
    }
    let(:registry_port) { '25695' }
    let(:public_ip) { '1.2.3.4' }
    let(:private_ip) { '5.6.7.8' }
    let(:internal_ip) { '127.0.0.1' }
    let(:vm_cid) { 'vm cid' }
    let(:disk_cid) { 'disk cid' }
    let(:state) { double('state', vm_cid: vm_cid, disk_cid: disk_cid)  }

    let(:cloud) { double(Bosh::Google::Cloud) }
    let(:compute_api) { double(Fog::Compute::Google) }
    let(:instances) { double(Fog::Compute::Google::Servers) }
    let(:instance) {
      double(Fog::Compute::Google::Server,
             private_ip_address: private_ip,
             public_ip_address: public_ip)
    }
    let(:disks) { double(Fog::Compute::Google::Disks) }
    let(:disk) { double(Fog::Compute::Google::Disk, size_gb: disk_size) }
    let(:disk_size) { 4 }

    before do
      allow(Bosh::Deployer::Registry).to receive(:new).and_return(registry)
      allow(Bosh::Deployer::SshServer).to receive(:new).and_return(ssh_server)
      allow(Bosh::Deployer::RemoteTunnel).to receive(:new).and_return(remote_tunnel)
    end

    describe '#remote_tunnel' do
      it 'should create a remote tunnel' do
        expect(instance_manager).to receive(:client_services_ip).and_return(public_ip)
        expect(registry).to receive(:port).and_return(registry_port)
        expect(remote_tunnel).to receive(:create).with(public_ip, registry_port)

        subject.remote_tunnel
      end
    end

    describe '#disk_model' do
      it 'should return nil' do
        expect(subject.disk_model).to be_nil
      end
    end

    describe '#update_specs' do
      let(:spec) { Bosh::Deployer::Specification.new(spec_properties, config) }
      let(:spec_properties) {
        {
          'networks' => { 'name' => 'net_1' },
          'properties' => {}
        }
      }
      let(:new_spec) {
        {
          'google' => new_google_spec.merge('registry' => registry_options)
        }
      }

      before do
        expect(config).to receive(:spec_properties).and_return(google_spec_properties)
      end

      context 'without google spec properties' do
        let(:google_spec_properties) { {} }
        let(:new_google_spec) { google_options }

        it 'should update specs with cloud properties' do
          subject.update_spec(spec)
          expect(spec.properties).to eql(new_spec)
        end
      end

      context 'with google spec properties' do
        let(:google_spec_properties) {
          {
            'google' => {
              'project' => 'new-project',
              'client_email' => 'new-client_email',
              'pkcs12_key' => 'new-pkcs12-key',
              'zone' => 'new-zone',
              'access_key_id' => 'new-access_key_id',
              'secret_access_key' => 'new-secret_access_key',
              'private_key' => 'spec/assets/fake-private.key'
            }
          }
        }
        let(:new_google_spec) { google_spec_properties['google'] }

        it 'should update specs with spec google spec properties' do
          subject.update_spec(spec)
          expect(spec.properties).to eql(new_spec)
        end
      end
    end

    describe '#start' do
      it 'should start services' do
        expect(registry).to receive(:start)

        subject.start
      end
    end

    describe '#stop' do
      it 'should stop services' do
        expect(registry).to receive(:stop)
        expect(instance_manager).to receive(:save_state)

        subject.stop
      end
    end

    describe '#client_services_ip' do
      before do
        expect(instance_manager).to receive(:state).and_return(state)
        expect(state).to receive(:vm_cid).and_return(vm_cid)
      end

      context 'when there is a Bosh vm' do
        before do
          expect(instance_manager).to receive(:cloud).and_return(cloud)
          expect(cloud).to receive(:compute_api).and_return(compute_api)
          expect(compute_api).to receive(:servers).and_return(instances)
          expect(instance_manager).to receive(:state).and_return(state)
          expect(instances).to receive(:get).with(vm_cid).and_return(instance)
        end

        context 'when vm has a public ip' do
          it 'should return the public ip' do
            expect(subject.client_services_ip).to eql(public_ip)
          end
        end

        context 'when vm has no public ip address' do
          let(:public_ip) { nil }

          it 'should return the private ip' do
            expect(subject.client_services_ip).to eql(private_ip)
          end
        end
      end

      context 'when there is not a Bosh vm' do
        let(:vm_cid) { nil }

        it 'should return the default client services ip' do
          expect(config).to receive(:client_services_ip).and_return(public_ip)

          expect(subject.client_services_ip).to eql(public_ip)
        end
      end
    end

    describe '#agent_services_ip' do
      before do
        expect(instance_manager).to receive(:state).and_return(state)
        expect(state).to receive(:vm_cid).and_return(vm_cid)
      end

      context 'when there is a Bosh vm' do
        before do
          expect(instance_manager).to receive(:cloud).and_return(cloud)
          expect(cloud).to receive(:compute_api).and_return(compute_api)
          expect(compute_api).to receive(:servers).and_return(instances)
          expect(instance_manager).to receive(:state).and_return(state)
          expect(instances).to receive(:get).with(vm_cid).and_return(instance)
        end

        it 'should return the private ip' do
          expect(subject.agent_services_ip).to eql(private_ip)
        end
      end

      context 'when there is not a Bosh vm' do
        let(:vm_cid) { nil }

        it 'should return the default agent services ip' do
          expect(config).to receive(:agent_services_ip).and_return(private_ip)

          expect(subject.agent_services_ip).to eql(private_ip)
        end
      end
    end

    describe '#internal_services_ip' do
      it 'should return the internal services ip' do
        expect(config).to receive(:internal_services_ip).and_return(internal_ip)

        expect(subject.internal_services_ip).to eql(internal_ip)
      end
    end

    describe '#persistent_disk_changed?' do
      before do
        expect(config).to receive(:resources).and_return(resources)
        expect(instance_manager).to receive(:state).and_return(state)
        expect(instance_manager).to receive(:cloud).and_return(cloud)
        expect(cloud).to receive(:compute_api).and_return(compute_api)
        expect(compute_api).to receive(:disks).and_return(disks)
        expect(disks).to receive(:get).with(disk_cid).and_return(disk)
      end

      context 'when disk size has changed' do
        let(:resources) { { 'persistent_disk' => 1024 } }

        it 'should return true' do
          expect(subject.persistent_disk_changed?).to be_truthy
        end
      end

      context 'when disk size has not changed' do
        let(:resources) { { 'persistent_disk' => disk_size * 1024 } }

        it 'should return false' do
          expect(subject.persistent_disk_changed?).to be_falsey
        end
      end
    end
  end
end
