# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe Cloud do
    let(:subject) { described_class }
    let(:cloud) { subject.new(cloud_options) }
    let(:cloud_options) do
      {
        'google' => google_options,
        'registry' => registry_options
      }
    end
    let(:google_project) { 'google_project' }
    let(:google_client_email) { 'google_client_email' }
    let(:google_pkcs12_key) { 'google_pkcs12_key' }
    let(:google_default_zone) { 'google_zone' }
    let(:google_access_key_id) { 'google_access_key_id' }
    let(:google_secret_access_key) { 'google_secret_access_key' }
    let(:google_options) do
      {
        'project' => google_project,
        'client_email' => google_client_email,
        'pkcs12_key' => google_pkcs12_key,
        'default_zone' => google_default_zone,
        'access_key_id' => google_access_key_id,
        'secret_access_key' => google_secret_access_key
      }
    end
    let(:registry_endpoint) { 'registry_endpoint' }
    let(:registry_user) { 'registry_user' }
    let(:registry_password) { 'registry_password' }
    let(:registry_options) do
      {
        'endpoint' => registry_endpoint,
        'user'     => registry_user,
        'password' => registry_password
      }
    end
    let(:image_identity) { 'image-identity' }
    let(:image) { double(Fog::Compute::Google::Image, identity: image_identity) }
    let(:instance_identity) { 'instance-identity' }
    let(:instance_disks) { [{ 'source' => disk_identity, 'boot' => true }] }
    let(:instance_zone) { google_default_zone }
    let(:instance) do
      double(Fog::Compute::Google::Server,
             identity: instance_identity, disks: instance_disks, zone: instance_zone)
    end
    let(:disk_identity) { 'disk-identity' }
    let(:disk_zone) { google_default_zone }
    let(:disk) do
      double(Fog::Compute::Google::Disk, identity: disk_identity, source: disk_identity, zone: disk_zone)
    end
    let(:device_name) { 'device-name' }
    let(:disk_snapshot_identity) { 'disk-snapshot-identity' }
    let(:disk_snapshot) { double(Fog::Compute::Google::Snapshot, identity: disk_snapshot_identity) }
    let(:resource_pool) { {} }
    let(:resource_pool_zone) { 'resource_pool_zone' }
    let(:agent_id) { 'agent-id' }
    let(:environment) { { 'bosh' => { 'password' => 'bosh-password' } } }
    let(:network_type) { 'dynamic' }
    let(:network_dns) { ['8.8.8.8'] }
    let(:cloud_properties) { {} }
    let(:dynamic_network) do
      {
        'type' => network_type,
        'dns' => network_dns,
        'cloud_properties' => cloud_properties
      }
    end
    let(:network_spec) { { 'default' => dynamic_network } }
    let(:agent_settings) do
      {
        'vm' => { 'id' => instance_identity },
        'agent_id' => agent_id,
        'networks' => network_spec,
        'disks' => { 'system' => '/dev/sda', 'persistent' => {} },
        'env' => environment
      }
    end
    let(:agent_settings_with_network) do
      settings = agent_settings
      settings['networks'] = network_spec
      settings
    end
    let(:persistent_disk) { { disk_identity => device_name } }
    let(:agent_settings_with_disk) do
      settings = agent_settings
      settings['disks']['persistent'] = persistent_disk
      settings
    end

    let(:compute_api) { double(Fog::Compute::Google) }
    let(:storage_api) { double(Fog::Storage::Google) }
    let(:disk_manager) { double(Bosh::Google::DiskManager) }
    let(:disk_snapshot_manager) { double(Bosh::Google::DiskSnapshotManager) }
    let(:image_manager) { double(Bosh::Google::ImageManager) }
    let(:instance_manager) { double(Bosh::Google::InstanceManager) }
    let(:network_manager) { double(Bosh::Google::NetworkManager) }
    let(:registry_manager) { double(Bosh::Google::RegistryManager) }
    let(:registry) { double(Bosh::Registry::Client) }

    before do
      allow(Fog::Compute).to receive(:new).and_return(compute_api)
      allow(Fog::Storage).to receive(:new).and_return(storage_api)
      allow(Bosh::Google::DiskManager).to receive(:new).with(compute_api).and_return(disk_manager)
      allow(Bosh::Google::DiskSnapshotManager).to receive(:new).with(compute_api).and_return(disk_snapshot_manager)
      allow(Bosh::Google::ImageManager).to receive(:new).with(compute_api, storage_api).and_return(image_manager)
      allow(Bosh::Google::InstanceManager).to receive(:new).with(compute_api).and_return(instance_manager)
      allow(Bosh::Google::NetworkManager).to receive(:new).with(compute_api, network_spec).and_return(network_manager)
      allow(Bosh::Google::RegistryManager).to receive(:new).with(registry_options).and_return(registry_manager)
    end

    describe '#new' do
      it 'should set attribute readers' do
        manager = subject.new(cloud_options)
        expect(manager.compute_api).to eql(compute_api)
        expect(manager.storage_api).to eql(storage_api)
      end

      it 'should initialize Compute api' do
        expect(Fog::Compute).to receive(:new).with(provider: 'Google',
                                                   google_project: google_project,
                                                   google_client_email: google_client_email,
                                                   google_key_string: Base64.decode64(google_pkcs12_key))

        subject.new(cloud_options)
      end

      it 'should raise a CloudError exception if cannot connect to Compute api' do
        expect(Fog::Compute).to receive(:new).and_raise(Fog::Errors::Error)

        expect do
          subject.new(cloud_options)
        end.to raise_error(Bosh::Clouds::CloudError,
                           'Unable to connect to the Google Compute Engine API. Check task debug log for details.')
      end

      it 'should initialize Storage api' do
        expect(Fog::Storage).to receive(:new).with(provider: 'Google',
                                                   google_storage_access_key_id: google_access_key_id,
                                                   google_storage_secret_access_key: google_secret_access_key)

        subject.new(cloud_options)
      end

      it 'should raise a CloudError exception if cannot connect to Storage api' do
        expect(Fog::Storage).to receive(:new).and_raise(Fog::Errors::Error)

        expect do
          subject.new(cloud_options)
        end.to raise_error(Bosh::Clouds::CloudError,
                           'Unable to connect to the Google Cloud Storage API. Check task debug log for details.')
      end

      context 'validates google options' do
        let(:google_options) { {} }

        it 'should raise a CloudError exception if there is a missing parameter' do
          expect do
            subject.new(cloud_options)
          end.to raise_error(Bosh::Clouds::CloudError, 'Missing configuration parameters: google:project, ' \
                                                       'google:client_email, google:pkcs12_key, ' \
                                                       'google:default_zone, ' \
                                                       'google:access_key_id, google:secret_access_key')
        end
      end

      context 'validates registry options' do
        let(:registry_options) { {} }

        it 'should raise a CloudError exception if there is a missing parameter' do
          expect do
            subject.new(cloud_options)
          end.to raise_error(Bosh::Clouds::CloudError,
                             'Missing configuration parameters: registry:endpoint, registry:user, registry:password')
        end
      end
    end

    describe '#create_stemcell' do
      let(:image_path) { 'file://image_path' }
      let(:image_name) { 'image-name' }
      let(:image_version) { 'image-version' }
      let(:image_description) { "#{image_name}/#{image_version}" }
      let(:infrastructure) { 'google' }
      let(:source_url) { 'gs://bucket-name/raw_disk.tar.gz' }
      let(:stemcell_properties) do
        {
          'name' => image_name,
          'version' => image_version,
          'infrastructure' => infrastructure,
          'source_url' => source_url
        }
      end

      context 'from a light stemcell' do
        it 'should create a stemcell' do
          expect(image_manager).to receive(:create_from_url).with(source_url, image_description).and_return(image)

          expect(cloud.create_stemcell(image_path, stemcell_properties)).to eql(image_identity)
        end
      end

      context 'from a regular stemcell' do
        let(:source_url) { nil }

        it 'should create a stemcell' do
          expect(image_manager).to receive(:create_from_tarball).with(image_path, image_description).and_return(image)

          expect(cloud.create_stemcell(image_path, stemcell_properties)).to eql(image_identity)
        end
      end

      context 'when infrastructure is not valid' do
        let(:infrastructure) { 'unknown' }

        it 'should raise a CloudError' do
          expect do
            cloud.create_stemcell(image_path, stemcell_properties)
          end.to raise_error(Bosh::Clouds::CloudError,
                             "Invalid Google Compute Engine stemcell, infrastructure is `#{infrastructure}'")
        end
      end
    end

    describe '#delete_stemcell' do
      it 'should delete a stemcell' do
        expect(image_manager).to receive(:delete).with(image_identity)

        cloud.delete_stemcell(image_identity)
      end
    end

    describe '#create_vm' do
      it 'should create a vm' do
        expect(image_manager).to receive(:get).with(image_identity).and_return(image)
        expect(instance_manager).to receive(:create)
          .with(google_default_zone, image, resource_pool, network_manager, registry_endpoint)
          .and_return(instance)
        expect(network_manager).to receive(:configure).with(instance)
        expect(registry_manager).to receive(:registry).and_return(registry)
        expect(registry).to receive(:endpoint).and_return(registry_endpoint)
        expect(registry_manager).to receive(:update).with(instance_identity, agent_settings)

        expect(
          cloud.create_vm(agent_id, image_identity, resource_pool, network_spec, nil, environment)
        ).to eql(instance_identity)
      end

      context 'with affinity to resource_pool' do
        let(:resource_pool) { { 'zone' => resource_pool_zone } }

        it 'should create a vm' do
          expect(image_manager).to receive(:get).with(image_identity).and_return(image)
          expect(instance_manager).to receive(:create)
            .with(resource_pool_zone, image, resource_pool, network_manager, registry_endpoint)
            .and_return(instance)
          expect(network_manager).to receive(:configure).with(instance)
          expect(registry_manager).to receive(:registry).and_return(registry)
          expect(registry).to receive(:endpoint).and_return(registry_endpoint)
          expect(registry_manager).to receive(:update).with(instance_identity, agent_settings)

          expect(
            cloud.create_vm(agent_id, image_identity, resource_pool, network_spec, nil, environment)
          ).to eql(instance_identity)
        end
      end

      context 'with affinity to disk' do
        before do
          expect(disk_manager).to receive(:get).with(disk_identity).and_return(disk)
        end

        let(:disk_locality) { [disk_identity] }

        context 'and no affinity to resource pool' do
          let(:disk_zone) { 'disk_zone' }

          before do
            expect(image_manager).to receive(:get).with(image_identity).and_return(image)
            expect(instance_manager).to receive(:create)
              .with(disk_zone, image, resource_pool, network_manager, registry_endpoint)
              .and_return(instance)
            expect(network_manager).to receive(:configure).with(instance)
            expect(registry_manager).to receive(:registry).and_return(registry)
            expect(registry).to receive(:endpoint).and_return(registry_endpoint)
            expect(registry_manager).to receive(:update).with(instance_identity, agent_settings)
          end

          it 'should create a vm' do
            expect(
              cloud.create_vm(agent_id, image_identity, resource_pool, network_spec, disk_locality, environment)
            ).to eql(instance_identity)
          end
        end

        context 'and affinity to resource pool' do
          let(:resource_pool) { { 'zone' => resource_pool_zone } }
          let(:disk_zone) { 'disk_zone' }

          it 'should raise a CloudError' do
            expect do
              cloud.create_vm(agent_id, image_identity, resource_pool, network_spec, disk_locality, environment)
            end.to raise_error(Bosh::Clouds::CloudError,
                               "Can't use multiple zones: `#{resource_pool_zone}, #{disk_zone}'")
          end
        end
      end

      context 'when create vm fails' do
        before do
          allow(registry_manager).to receive(:registry).and_return(registry)
          allow(registry).to receive(:endpoint).and_return(registry_endpoint)
        end

        it 'should not delete the vm if it has not been not created' do
          expect(image_manager).to receive(:get).and_raise(Bosh::Clouds::CloudError)

          expect do
            cloud.create_vm(agent_id, image_identity, resource_pool, network_spec, nil, environment)
          end.to raise_error(Bosh::Clouds::CloudError)
        end

        it 'should delete the vm if it has been created' do
          expect(image_manager).to receive(:get).with(image_identity).and_return(image)
          expect(instance_manager).to receive(:create).and_return(instance)
          expect(network_manager).to receive(:configure).with(instance).and_raise(Bosh::Clouds::CloudError)
          expect(registry).to receive(:endpoint).and_return(registry_endpoint)
          expect(instance_manager).to receive(:terminate).with(instance_identity)

          expect do
            cloud.create_vm(agent_id, image_identity, resource_pool, network_spec, nil, environment)
          end.to raise_error(Bosh::Clouds::VMCreationFailed)
        end
      end
    end

    describe '#delete_vm' do
      it 'should delete a vm' do
        expect(instance_manager).to receive(:terminate).with(instance_identity)
        expect(registry_manager).to receive(:delete).with(instance_identity)

        cloud.delete_vm(instance_identity)
      end
    end

    describe '#reboot_vm' do
      it 'should reboot a vm' do
        expect(instance_manager).to receive(:reboot).with(instance_identity)

        cloud.reboot_vm(instance_identity)
      end
    end

    describe '#has_vm?' do
      it 'should return true if vm exist' do
        expect(instance_manager).to receive(:exists?).with(instance_identity).and_return(true)

        expect(cloud.has_vm?(instance_identity)).to be_truthy
      end

      it 'should return false if vm does not exist' do
        expect(instance_manager).to receive(:exists?).with(instance_identity).and_return(false)

        expect(cloud.has_vm?(instance_identity)).to be_falsey
      end
    end

    describe '#set_vm_metadata' do
      it 'should set metadata for a vm' do
        expect(instance_manager).to receive(:set_metadata).with(instance_identity, job: 'job', index: 'index')

        cloud.set_vm_metadata(instance_identity, job: 'job', index: 'index')
      end
    end

    describe '#configure_networks' do
      it 'should configure networks for a vm' do
        expect(instance_manager).to receive(:get).with(instance_identity).and_return(instance)
        expect(network_manager).to receive(:update).with(instance)
        expect(registry_manager).to receive(:read).with(instance_identity).and_return(agent_settings)
        expect(registry_manager).to receive(:update).with(instance_identity, agent_settings_with_network)

        cloud.configure_networks(instance_identity, network_spec)
      end
    end

    describe '#create_disk' do
      context 'without vm affinity' do
        it 'should create a disk' do
          expect(disk_manager).to receive(:create_blank).with(1024, google_default_zone).and_return(disk)

          expect(cloud.create_disk(1024)).to eql(disk_identity)
        end
      end

      context 'with vm affinity' do
        let(:instance_zone) { 'other_zone' }

        before do
          expect(instance_manager).to receive(:get).with(instance_identity).and_return(instance)
        end

        it 'should create a disk on same zone as vm' do
          expect(disk_manager).to receive(:create_blank).with(1024, instance_zone).and_return(disk)

          expect(cloud.create_disk(1024, instance_identity)).to eql(disk_identity)
        end
      end
    end

    describe '#delete_disk' do
      it 'should delete a disk' do
        expect(disk_manager).to receive(:delete).with(disk_identity)

        cloud.delete_disk(disk_identity)
      end
    end

    describe '#attach_disk' do
      it 'should attach a disk' do
        expect(instance_manager).to receive(:get).with(instance_identity).and_return(instance)
        expect(disk_manager).to receive(:get).with(disk_identity).and_return(disk)
        expect(instance_manager).to receive(:attach_disk).with(instance, disk).and_return(device_name)
        expect(registry_manager).to receive(:read).with(instance_identity).and_return(agent_settings)
        expect(registry_manager).to receive(:update).with(instance_identity, agent_settings_with_disk)

        cloud.attach_disk(instance_identity, disk_identity)
      end
    end

    describe '#detach_disk' do
      it 'should detach a disk' do
        expect(instance_manager).to receive(:get).with(instance_identity).and_return(instance)
        expect(disk_manager).to receive(:get).with(disk_identity).and_return(disk)
        expect(instance_manager).to receive(:detach_disk).with(instance, disk)
        expect(registry_manager).to receive(:read).with(instance_identity).and_return(agent_settings_with_disk)
        expect(registry_manager).to receive(:update).with(instance_identity, agent_settings)

        cloud.detach_disk(instance_identity, disk_identity)
      end
    end

    describe '#get_disks' do
      it 'should return the list of attached disks of a vm' do
        expect(instance_manager).to receive(:attached_disks).with(instance_identity).and_return([disk_identity])

        expect(cloud.get_disks(instance_identity)).to eql([disk_identity])
      end
    end

    describe '#snapshot_disk' do
      it 'should take a snapshot of a disk' do
        expect(disk_manager).to receive(:get).with(disk_identity).and_return(disk)
        expect(disk_snapshot_manager).to receive(:create).with(disk, {}).and_return(disk_snapshot)

        expect(cloud.snapshot_disk(disk_identity, {})).to eql(disk_snapshot_identity)
      end
    end

    describe '#delete_snapshot' do
      it 'should delete a disk snapshot' do
        expect(disk_snapshot_manager).to receive(:delete).with(disk_snapshot_identity)

        cloud.delete_snapshot(disk_snapshot_identity)
      end
    end

    describe '#validate_deployment' do
      it 'should raise a NotImplemented exception' do
        expect do
          cloud.validate_deployment({}, {})
        end.to raise_error(Bosh::Clouds::NotImplemented)
      end
    end
  end
end
