# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe InstanceManager do
    let(:compute_api) { double(Fog::Compute::Google) }
    let(:subject) { described_class.new(compute_api) }

    let(:zone) { 'zone' }
    let(:instances) { double(Fog::Compute::Google::Servers) }
    let(:instance_identity) { 'instance-identity' }
    let(:instance_state) { :running }
    let(:instance_disks) { [] }
    let(:instance) {
      double(Fog::Compute::Google::Server, identity: instance_identity, state: instance_state, disks: instance_disks)
    }
    let(:image_identity) { 'image-identity' }
    let(:image) {
      double(Fog::Compute::Google::Image, identity: image_identity, self_link: image_identity)
    }
    let(:disk_identity) { 'disk-identity' }
    let(:disk) {
      double(Fog::Compute::Google::Disk, identity: disk_identity, self_link: disk_identity)
    }
    let(:operation) { double(Fog::Compute::Google::Operation) }

    before do
      allow(compute_api).to receive(:servers).and_return(instances)
    end

    describe '#get' do
      it 'should return an instance' do
        expect(instances).to receive(:get).with(instance_identity).and_return(instance)

        expect(subject.get(instance_identity)).to eql(instance)
      end

      it 'should raise a VMNotFound exception if instance is not found' do
        expect(instances).to receive(:get).with(instance_identity).and_return(nil)

        expect do
          subject.get(instance_identity)
        end.to raise_error(Bosh::Clouds::VMNotFound)
      end
    end

    describe '#create' do
      let(:unique_name) { SecureRandom.uuid }
      let(:flavors) { double(Fog::Compute::Google::Flavors) }
      let(:flavor_name) { 'flavor-name' }
      let(:flavor) { double(Fog::Compute::Google::Flavor, name: flavor_name, description: flavor_name) }
      let(:resource_pool) { { 'instance_type' => flavor_name } }
      let(:registry_endpoint) { 'registry_endpoint' }
      let(:network_dns) { ['8.8.8.8'] }
      let(:network_name) { 'network-name' }
      let(:tags) { %w(tag1 tag2) }
      let(:external_ip) { true }
      let(:can_ip_forward) { true }
      let(:boot_disk) do
        [{
          'boot' => true,
          'type' => 'PERSISTENT',
          'autoDelete' => true,
          'initializeParams' => { 'sourceImage' => image.self_link }
        }]
      end
      let(:user_data) do
        {
          'instance' => { 'name' => "vm-#{unique_name}" },
          'registry' => { 'endpoint' => registry_endpoint },
          'dns' => { 'nameserver' => network_dns }
        }
      end
      let(:automatic_restart) { false }
      let(:on_host_maintenance) { 'MIGRATE' }
      let(:service_accounts) { nil }
      let(:instance_params) do
        {
          name: "vm-#{unique_name}",
          zone: zone,
          description: 'Instance managed by BOSH',
          machine_type: flavor_name,
          disks: boot_disk,
          metadata: { 'user_data' => Yajl::Encoder.encode(user_data) },
          auto_restart: automatic_restart,
          on_host_maintenance: on_host_maintenance,
          service_accounts: service_accounts,
          network: network_name,
          tags: tags,
          can_ip_forward: can_ip_forward
        }
      end
      let(:network_manager) { double(Bosh::Google::NetworkManager) }

      before do
        allow(subject).to receive(:generate_unique_name).and_return(unique_name)
        allow(compute_api).to receive(:flavors).and_return(flavors)
      end

      it 'should create a server' do
        expect(flavors).to receive(:get).with(flavor_name, zone).and_return(flavor)
        expect(network_manager).to receive(:dns).and_return(network_dns)
        expect(network_manager).to receive(:network_name).twice.and_return(network_name)
        expect(network_manager).to receive(:tags).and_return(tags)
        expect(network_manager).to receive(:ephemeral_external_ip).and_return(external_ip)
        expect(network_manager).to receive(:ip_forwarding).and_return(can_ip_forward)
        expect(instances).to receive(:create).with(instance_params).and_return(instance)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(instance)
        expect(instance).to receive(:reload).and_return(instance)

        expect(subject.create(zone, image, resource_pool, network_manager, registry_endpoint)).to eql(instance)
      end

      context 'when dns list is empty' do
        let(:user_data) do
          {
            'instance' => { 'name' => "vm-#{unique_name}" },
            'registry' => { 'endpoint' => registry_endpoint }
          }
        end

        it 'should create a server with appropiate parms' do
          expect(flavors).to receive(:get).with(flavor_name, zone).and_return(flavor)
          expect(network_manager).to receive(:dns).and_return([])
          expect(network_manager).to receive(:network_name).twice.and_return(network_name)
          expect(network_manager).to receive(:tags).and_return(tags)
          expect(network_manager).to receive(:ephemeral_external_ip).and_return(external_ip)
          expect(network_manager).to receive(:ip_forwarding).and_return(can_ip_forward)
          expect(instances).to receive(:create).with(instance_params).and_return(instance)
          expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(instance)
          expect(instance).to receive(:reload).and_return(instance)

          expect(subject.create(zone, image, resource_pool, network_manager, registry_endpoint)).to eql(instance)
        end
      end

      context 'when external ip is set to false' do
        let(:external_ip) { false }

        it 'should create a server with appropiate parms' do
          expect(flavors).to receive(:get).with(flavor_name, zone).and_return(flavor)
          expect(network_manager).to receive(:dns).and_return(network_dns)
          expect(network_manager).to receive(:network_name).twice.and_return(network_name)
          expect(network_manager).to receive(:tags).and_return(tags)
          expect(network_manager).to receive(:ephemeral_external_ip).and_return(external_ip)
          expect(network_manager).to receive(:ip_forwarding).and_return(can_ip_forward)
          expect(instances).to receive(:create).with(instance_params.merge(external_ip: external_ip))
                               .and_return(instance)
          expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(instance)
          expect(instance).to receive(:reload).and_return(instance)

          expect(subject.create(zone, image, resource_pool, network_manager, registry_endpoint)).to eql(instance)
        end
      end

      context 'when resource pool cloud property' do
        before do
          allow(flavors).to receive(:get).with(flavor_name, zone).and_return(flavor)
          allow(network_manager).to receive(:dns).and_return(network_dns)
          allow(network_manager).to receive(:network_name).and_return(network_name)
          allow(network_manager).to receive(:tags).and_return(tags)
          allow(network_manager).to receive(:ephemeral_external_ip).and_return(external_ip)
          allow(network_manager).to receive(:ip_forwarding).and_return(can_ip_forward)
          allow(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(instance)
          allow(instance).to receive(:reload).and_return(instance)
        end

        context 'instance_type' do
          context 'is not set' do
            let(:resource_pool) { {} }

            it 'should raise a CloudError exception' do
              expect do
                subject.create(zone, image, resource_pool, network_manager, registry_endpoint)
              end.to raise_error(Bosh::Clouds::CloudError,
                                 "Missing `instance_type' param at resource pool cloud properties")
            end
          end

          context 'is set to an unexisting machine type' do
            let(:resource_pool) { { 'instance_type' => 'unknown' } }

            it 'should raise a CloudError exception' do
              expect(flavors).to receive(:get).with('unknown', zone).and_return(nil)

              expect do
                subject.create(zone, image, resource_pool, network_manager, registry_endpoint)
              end.to raise_error(Bosh::Clouds::CloudError, "Machine Type `unknown' not found")
            end
          end
        end

        context 'automatic_restart' do
          let(:resource_pool) { { 'instance_type' => flavor_name, 'automatic_restart' => automatic_restart } }

          context 'is set to true' do
            let(:automatic_restart) { true }

            it 'should create a server with appropiate parms' do
              expect(instances).to receive(:create).with(instance_params).and_return(instance)

              expect(subject.create(zone, image, resource_pool, network_manager, registry_endpoint)).to eql(instance)
            end
          end

          context 'is set to false' do
            let(:automatic_restart) { false }

            it 'should create a server with appropiate parms' do
              expect(instances).to receive(:create).with(instance_params).and_return(instance)

              expect(subject.create(zone, image, resource_pool, network_manager, registry_endpoint)).to eql(instance)
            end
          end

          context 'is not a Boolean' do
            let(:automatic_restart) { 'automatic-restart' }

            it 'should raise a CloudError exception' do
              expect do
                subject.create(zone, image, resource_pool, network_manager, registry_endpoint)
              end.to raise_error(Bosh::Clouds::CloudError,
                                 "Invalid `automatic_restart' property: Boolean expected, `String' provided")
            end
          end
        end

        context 'on_host_maintenance' do
          let(:resource_pool) { { 'instance_type' => flavor_name, 'on_host_maintenance' => on_host_maintenance } }

          context 'is set to MIGRATE' do
            let(:on_host_maintenance) { 'MIGRATE' }

            it 'should create a server with appropiate parms' do
              expect(instances).to receive(:create).with(instance_params).and_return(instance)

              expect(subject.create(zone, image, resource_pool, network_manager, registry_endpoint)).to eql(instance)
            end
          end

          context 'is set to TERMINATE' do
            let(:on_host_maintenance) { 'TERMINATE' }

            it 'should create a server with appropiate parms' do
              expect(instances).to receive(:create).with(instance_params).and_return(instance)

              expect(subject.create(zone, image, resource_pool, network_manager, registry_endpoint)).to eql(instance)
            end
          end

          context 'is not a String' do
            let(:on_host_maintenance) { ['on_host_maintenance'] }

            it 'should raise a CloudError exception' do
              expect do
                subject.create(zone, image, resource_pool, network_manager, registry_endpoint)
              end.to raise_error(Bosh::Clouds::CloudError,
                                 "Invalid `on_host_maintenance' property: String expected, `Array' provided")
            end
          end

          context 'is not a valid option' do
            let(:on_host_maintenance) { 'on_host_maintenance' }

            it 'should raise a CloudError exception' do
              expect do
                subject.create(zone, image, resource_pool, network_manager, registry_endpoint)
              end.to raise_error(Bosh::Clouds::CloudError,
                                 "Invalid `on_host_maintenance' property: only `MIGRATE' or `TERMINATE' are supported")
            end
          end
        end

        context 'service_scopes' do
          let(:resource_pool) { { 'instance_type' => flavor_name, 'service_scopes' => service_scopes } }

          context 'is an Array' do
            let(:service_scopes) { %w(compute.readonly devstorage.read_write) }
            let(:service_accounts) { service_scopes }

            it 'should create a server with appropiate parms' do
              expect(instances).to receive(:create).with(instance_params).and_return(instance)

              expect(subject.create(zone, image, resource_pool, network_manager, registry_endpoint)).to eql(instance)
            end
          end

          context 'is an empty Array' do
            let(:service_scopes) { [] }

            it 'should create a server with appropiate parms' do
              expect(instances).to receive(:create).with(instance_params).and_return(instance)

              expect(subject.create(zone, image, resource_pool, network_manager, registry_endpoint)).to eql(instance)
            end
          end

          context 'is not an Array' do
            let(:service_scopes) { 'service_scopes' }

            it 'should raise a CloudError exception' do
              expect do
                subject.create(zone, image, resource_pool, network_manager, registry_endpoint)
              end.to raise_error(Bosh::Clouds::CloudError,
                                 "Invalid `service_scopes' property: Array expected, `String' provided")
            end
          end
        end
      end

      it 'should raise a VMCreationFailed exception when unable to create a vm' do
        expect(subject).to receive(:create_params).and_return({})
        expect(instances).to receive(:create).and_return(instance)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(instance)
                                                     .and_raise(Bosh::Clouds::CloudError)

        expect do
          subject.create(zone, image, resource_pool, network_manager, registry_endpoint)
        end.to raise_error(Bosh::Clouds::VMCreationFailed)
      end
    end

    describe '#terminate' do
      it 'should terminate an instance' do
        expect(instances).to receive(:get).with(instance_identity).and_return(instance)
        expect(instance).to receive(:destroy).and_return(operation)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

        subject.terminate(instance_identity)
      end
    end

    describe '#reboot' do
      it 'should reboot an instance' do
        expect(instances).to receive(:get).with(instance_identity).and_return(instance)
        expect(instance).to receive(:reboot).and_return(operation)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

        subject.reboot(instance_identity)
      end
    end

    describe '#exists?' do
      context 'when instance exist' do
        before do
          expect(instances).to receive(:get).with(instance_identity).and_return(instance)
        end

        it 'should return true' do
          expect(subject.exists?(instance_identity)).to be_truthy
        end
      end

      context 'when instance does not exist' do
        before do
          expect(instances).to receive(:get).with(instance_identity).and_return(nil)
        end

        it 'should return false' do
          expect(subject.exists?(instance_identity)).to be_falsey
        end
      end
    end

    describe '#set_metadata' do
      let(:metadata) { { 'new_key' => 'new_value' } }
      let(:old_metadata) { { 'items' => [{ 'key' => 'old_key', 'value' => 'old_value' }] } }
      let(:new_metadata) { { 'old_key' => 'old_value', 'new_key' => 'new_value' } }

      it 'should do nothing when metadata is nil' do
        subject.set_metadata(instance_identity, nil)
      end

      it 'should do nothing when metadata is empty' do
        subject.set_metadata(instance_identity, {})
      end

      it 'should trim key and value length' do
        expect(instances).to receive(:get).with(instance_identity).and_return(instance)
        expect(instance).to receive(:metadata).and_return({})
        expect(instance).to receive(:set_metadata).with('x' * 128 => 'y' * 32_768).and_return(operation)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

        subject.set_metadata(instance_identity, 'x' * 129 => 'y' * 32_769)
      end

      it 'should preserve old instance metadata' do
        expect(instances).to receive(:get).with(instance_identity).and_return(instance)
        expect(instance).to receive(:metadata).and_return(old_metadata)
        expect(instance).to receive(:set_metadata).with(new_metadata).and_return(operation)
        expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

        subject.set_metadata(instance_identity, metadata)
      end
    end

    describe '#attach_disk' do
      context 'when disk can be attached' do
        let(:device_name) { 'device-name' }
        let(:instance_disks) { [{ 'source' => disk_identity, 'deviceName' => device_name }] }

        it 'should attach a disk to an instance' do
          expect(instance).to receive(:attach_disk).with(disk.self_link, writable: true).and_return(operation)
          expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)
          expect(instance).to receive(:reload)

          expect(subject.attach_disk(instance, disk)).to eql(device_name)
        end
      end

      context 'when disk cannot be attached' do
        let(:instance_disks) { [] }

        it 'should raise a CloudError exception' do
          expect(instance).to receive(:attach_disk).with(disk.self_link, writable: true).and_return(operation)
          expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)
          expect(instance).to receive(:reload)

          expect do
            subject.attach_disk(instance, disk)
          end.to raise_error(Bosh::Clouds::CloudError,
                             "Unable to attach disk `#{disk_identity}' to vm `#{instance_identity}'")
        end
      end
    end

    describe '#detach_disk' do
      context 'when disk is attached to the instance' do
        let(:device_name) { 'device-name' }
        let(:instance_disks) { [{ 'source' => disk_identity, 'deviceName' => device_name }] }

        it 'should detach the disk from an instance' do
          expect(instance).to receive(:detach_disk).with(device_name).and_return(operation)
          expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

          subject.detach_disk(instance, disk)
        end
      end

      context 'when disk is not attached to the instance' do
        let(:instance_disks) { [] }

        it 'should raise a DiskNotAttached exception' do
          expect(instance).to_not receive(:detach_disk)

          expect do
            subject.detach_disk(instance, disk)
          end.to raise_error(Bosh::Clouds::DiskNotAttached)
        end
      end
    end

    describe '#attached_disks' do
      context 'when instance has attached disks' do
        let(:instance_disks) { [{ 'source' => disk_identity }] }

        it 'should return the list of disk identities' do
          expect(instances).to receive(:get).with(instance_identity).and_return(instance)

          expect(subject.attached_disks(instance_identity)).to eql([disk_identity])
        end
      end

      context 'when instance does not have attached disks' do
        let(:instance_disks) { [] }

        it 'should return an empty array' do
          expect(instances).to receive(:get).with(instance_identity).and_return(instance)

          expect(subject.attached_disks(instance_identity)).to eql([])
        end
      end
    end
  end
end
