# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe NetworkManager do
    let(:subject) { described_class }

    let(:cloud_properties) { {} }
    let(:dynamic_network_spec) do
      {
        'type' => 'dynamic',
        'cloud_properties' => cloud_properties
      }
    end
    let(:vip_network_spec) do
      {
        'type' => 'vip',
        'cloud_properties' => {}
      }
    end

    let(:public_ip_address) { nil }
    let(:compute_api) { double(Fog::Compute::Google) }
    let(:instance) do
      double(Fog::Compute::Google::Server,
             identity: instance_identity,
             zone_name: instance_zone,
             self_link: instance_self_link,
             network_interfaces: [instance_network_interface],
             can_ip_forward: instance_ip_forwarding,
             tags: { 'items' => instance_tags },
             public_ip_address: public_ip_address)
    end
    let(:instance_identity) { 'instance-identity' }
    let(:instance_zone) { 'instance-zone' }
    let(:instance_self_link) { 'instance-self_link' }
    let(:instance_network_interface) do
      { 'network' => instance_network_interface_network,
        'name' => instance_network_interface_name,
        'accessConfigs' => [instance_network_interface_access_config]
      }
    end
    let(:instance_network_interface_access_config) { { 'name' => access_config_name } }
    let(:access_config_name) { 'External NAT' }
    let(:instance_network_interface_network) { 'instance-network-interface-network' }
    let(:instance_network_interface_name) { 'instance-network-interface-name' }
    let(:instance_ip_forwarding) { false }
    let(:instance_tags) { %w(tag1 tag2) }
    let(:addresses) { double(Fog::Compute::Google::Addresses) }
    let(:address) { double(Fog::Compute::Google::Address) }
    let(:networks) { double(Fog::Compute::Google::Networks) }
    let(:target_pools) { double(Fog::Compute::Google::TargetPools) }
    let(:operations) { double(Fog::Compute::Google::Operations) }
    let(:operation) { double(Fog::Compute::Google::Operation) }

    describe '#new' do
      it 'should set attribute readers' do
        manager = subject.new(compute_api, 'dynamic' => dynamic_network_spec, 'vip' => vip_network_spec)

        expect(manager.dynamic_network).to be_a_kind_of(Bosh::Google::DynamicNetwork)
        expect(manager.vip_network).to be_a_kind_of(Bosh::Google::VipNetwork)
      end

      it 'validates network spec is a Hash' do
        expect do
          subject.new(compute_api, 'network_spec')
        end.to raise_error(Bosh::Clouds::CloudError, "Invalid network spec: Hash expected, `String' provided")
      end

      it 'validates there is only one dynamic network' do
        expect do
          subject.new(compute_api, 'dynamic_1' => dynamic_network_spec, 'dynamic_2' => dynamic_network_spec)
        end.to raise_error(Bosh::Clouds::CloudError, "Must have exactly one `dynamic' network per instance")
      end

      it 'validates there is only one vip network' do
        expect do
          subject.new(compute_api, 'vip_1' => vip_network_spec, 'vip_2' => vip_network_spec)
        end.to raise_error(Bosh::Clouds::CloudError, "Must have exactly one `vip' network per instance")
      end

      it 'validates network type is supported' do
        expect do
          subject.new(compute_api, 'default' => { 'type' => 'unknown' })
        end.to raise_error(Bosh::Clouds::CloudError,
                           "Invalid network type `unknown': only `dynamic' and 'vip' are supported")
      end

      it 'validates at least one dynamic network is defined' do
        expect do
          subject.new(compute_api, 'vip_1' => vip_network_spec)
        end.to raise_error(Bosh::Clouds::CloudError, "At least one `dynamic' network should be defined")
      end
    end

    describe '#configure' do
      let(:dynamic_network) { double(Bosh::Google::DynamicNetwork, cloud_properties: cloud_properties) }
      let(:vip_network) { double(Bosh::Google::VipNetwork) }

      before do
        allow(Bosh::Google::DynamicNetwork).to receive(:new).and_return(dynamic_network)
        allow(Bosh::Google::VipNetwork).to receive(:new).and_return(vip_network)
      end

      context 'when there is a vip network' do
        let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec, 'vip' => vip_network_spec) }

        it 'should configure dynamic and vip networks' do
          expect(dynamic_network).to receive(:configure).with(compute_api, instance)
          expect(vip_network).to receive(:configure).with(compute_api, instance)

          manager.configure(instance)
        end
      end

      context 'when there is not a vip network' do
        let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec) }

        before do
          expect(dynamic_network).to receive(:configure).with(compute_api, instance)
          expect(vip_network).to_not receive(:configure)
        end

        context 'and instance does not have any public ip associated' do
          let(:public_ip_address) { nil }

          it 'should configure dynamic network' do
            manager.configure(instance)
          end
        end

        context 'and instance has a public ip associated' do
          let(:public_ip_address) { '1.2.3.4' }

          before do
            allow(compute_api).to receive(:addresses).and_return(addresses)
          end

          context 'that is ephemeral' do
            it 'should configure dynamic network' do
              expect(addresses).to receive(:get_by_ip_address).with(public_ip_address).and_return(nil)

              manager.configure(instance)
            end
          end

          context 'that is a static IP' do
            it 'should should configure dynamic network and dessasociate the static IP' do
              expect(addresses).to receive(:get_by_ip_address).with(public_ip_address).and_return(address)
              expect(address).to receive(:server=).with(nil)
              expect(instance).to receive(:reload)

              manager.configure(instance)
            end
          end
        end
      end

      context 'when there is a target pool' do
        let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec, 'vip' => vip_network_spec) }
        let(:cloud_properties) { { 'target_pool' => target_pool_name } }
        let(:target_pool) do
          double(Fog::Compute::Google::TargetPool,
                 identity: target_pool_name,
                 instances: instances)
        end
        let(:target_pool_name) { 'target-pool' }
        let(:instances) { nil }

        before do
          expect(compute_api).to receive(:target_pools).and_return(target_pools)
        end

        context 'and it is not yet associated with the instance' do
          it 'should configure dynamic and vip networks and associate a target pool to the instance' do
            expect(dynamic_network).to receive(:configure).with(compute_api, instance)
            expect(vip_network).to receive(:configure).with(compute_api, instance)
            expect(target_pools).to receive(:get).with(target_pool_name).and_return(target_pool)
            expect(target_pool).to receive(:add_instance).with(instance)

            manager.configure(instance)
          end
        end

        context 'and it is already associated with the instance' do
          let(:instances) { [instance_self_link] }

          it 'should configure dynamic and vip networks' do
            expect(dynamic_network).to receive(:configure).with(compute_api, instance)
            expect(vip_network).to receive(:configure).with(compute_api, instance)
            expect(target_pools).to receive(:get).with(target_pool_name).and_return(target_pool)
            expect(target_pool).to_not receive(:add_instance).with(instance)

            manager.configure(instance)
          end
        end
      end
    end

    describe '#update' do
      let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec) }

      before do
        allow(manager).to receive(:configure).with(instance)
      end

      context 'when network' do
        let(:cloud_properties) { { 'network' => network_name } }
        let(:network) { double(Fog::Compute::Google::Network) }

        before do
          allow(manager).to receive(:update_ephemeral_external_ip).with(instance)
          allow(manager).to receive(:update_ip_forwarding).with(instance)
          allow(manager).to receive(:update_tags).with(instance)
          allow(compute_api).to receive(:networks).and_return(networks)
          allow(networks).to receive(:get).with(network_name).and_return(network)
        end

        context 'has changed' do
          let(:network_name) { 'network_name' }

          it 'should raise a NotSupported exception' do
            expect do
              manager.update(instance)
            end.to raise_error(Bosh::Clouds::NotSupported,
                               "Network change requires VM recreation: `#{instance_network_interface_network}' "\
                               "to `#{network_name}'")
          end
        end

        context 'has not changed' do
          let(:network_name) { instance_network_interface_network }

          it 'should do nothing' do
            manager.update(instance)
          end
        end
      end

      context 'when ephemeral_external_ip' do
        let(:cloud_properties) { { 'ephemeral_external_ip' => ephemeral_external_ip } }
        let(:response) { Excon::Response.new(body: { 'name' => 'name', 'zone' => 'zone' }) }

        before do
          allow(manager).to receive(:update_network).with(instance)
          allow(manager).to receive(:update_ip_forwarding).with(instance)
          allow(manager).to receive(:update_tags).with(instance)
        end

        context 'is set' do
          let(:ephemeral_external_ip) { true }

          context 'and instance has a public IP' do
            let(:public_ip_address) { '1.2.3.4' }

            it 'should do nothing' do
              manager.update(instance)
            end
          end

          context 'and instance has no public IP' do
            let(:public_ip_address) { nil }

            it 'should associate an ephemeral IP to the instance' do
              expect(compute_api).to receive(:add_server_access_config)
                .with(instance_identity, instance_zone, instance_network_interface_name)
                .and_return(response)
              expect(compute_api).to receive(:operations).and_return(operations)
              expect(operations).to receive(:get).and_return(operation)
              expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

              manager.update(instance)
            end
          end
        end

        context 'is not set' do
          let(:ephemeral_external_ip) { false }

          context 'and instance has a public IP' do
            let(:public_ip_address) { '1.2.3.4' }

            before do
              expect(compute_api).to receive(:addresses).and_return(addresses)
            end

            context 'that is an static ip' do
              it 'should do nothing' do
                expect(addresses).to receive(:get_by_ip_address).and_return(address)

                manager.update(instance)
              end
            end

            context 'that is not an static ip' do
              it 'should deassociate the ephemeral IP from the instance' do
                expect(addresses).to receive(:get_by_ip_address).and_return(nil)
                expect(compute_api).to receive(:delete_server_access_config)
                  .with(instance_identity,
                        instance_zone,
                        instance_network_interface_name,
                        access_config: access_config_name)
                  .and_return(response)
                expect(compute_api).to receive(:operations).and_return(operations)
                expect(operations).to receive(:get).and_return(operation)
                expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

                manager.update(instance)
              end
            end
          end

          context 'and instance has no ephemeral IP' do
            let(:public_ip_address) { nil }

            it 'should do nothing' do
              manager.update(instance)
            end
          end
        end
      end

      context 'when ip_forwarding' do
        let(:cloud_properties) { { 'ip_forwarding' => ip_forwarding } }

        before do
          allow(manager).to receive(:update_network).with(instance)
          allow(manager).to receive(:update_ephemeral_external_ip).with(instance)
          allow(manager).to receive(:update_tags).with(instance)
        end

        context 'has changed' do
          let(:ip_forwarding) { true }

          it 'should raise a NotSupported exception' do
            expect do
              manager.update(instance)
            end.to raise_error(Bosh::Clouds::NotSupported,
                               "IP forwarding change requires VM recreation: `#{instance_ip_forwarding}' "\
                               "to `#{ip_forwarding}'")
          end
        end

        context 'has not changed' do
          let(:ip_forwarding) { instance_ip_forwarding }

          it 'should do nothing' do
            manager.update(instance)
          end
        end
      end

      context 'tags' do
        let(:cloud_properties) { { 'tags' => tags } }

        before do
          allow(manager).to receive(:update_network).with(instance)
          allow(manager).to receive(:update_ephemeral_external_ip).with(instance)
          allow(manager).to receive(:update_ip_forwarding).with(instance)
        end

        context 'has changed' do
          context 'with new tags' do
            let(:tags) { %w(tag3 tag4) }

            it 'should update instance tags' do
              expect(instance).to receive(:set_tags).with(tags).and_return(operation)
              expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

              manager.update(instance)
            end
          end

          context 'with no tags' do
            let(:tags) { [] }

            it 'should update instance tags' do
              expect(instance).to receive(:set_tags).with(tags).and_return(operation)
              expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)

              manager.update(instance)
            end
          end
        end

        context 'has not changed' do
          let(:tags) { instance_tags }

          it 'should do nothing' do
            manager.update(instance)
          end
        end
      end
    end

    describe '#dns' do
      let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec) }

      context 'when property is set at network spec' do
        let(:dns) { ['8.8.8.8'] }
        let(:dynamic_network_spec) do
          {
            'type' => 'dynamic',
            'dns' => dns
          }
        end

        it 'should return an array of dns' do
          expect(manager.dns).to eql(dns)
        end
      end

      context 'when property is not set at network spec' do
        let(:dynamic_network_spec) do
          {
            'type' => 'dynamic'
          }
        end

        it 'should return an empty array' do
          expect(manager.dns).to eql([])
        end
      end

      context 'when property is nil at network spec' do
        let(:dynamic_network_spec) do
          {
            'type' => 'dynamic',
            'dns' => nil
          }
        end

        it 'should return an empty array' do
          expect(manager.dns).to eql([])
        end
      end

      context 'when property set at network spec is not an Array' do
        let(:dynamic_network_spec) do
          {
            'type' => 'dynamic',
            'dns' => 'dns'
          }
        end

        it 'should raise a CloudError exception' do
          expect do
            manager.dns
          end.to raise_error(Bosh::Clouds::CloudError, "Invalid `dns' property: Array expected, `String' provided")
        end
      end
    end

    describe '#network_name' do
      let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec) }
      let(:network) { double(Fog::Compute::Google::Network) }

      before do
        allow(compute_api).to receive(:networks).and_return(networks)
      end

      context 'when property is not set at cloud properties' do
        let(:cloud_properties) { {} }

        it 'should return default network' do
          expect(networks).to receive(:get).with(Bosh::Google::NetworkManager::DEFAULT_NETWORK).and_return(network)

          expect(manager.network_name).to be(Bosh::Google::NetworkManager::DEFAULT_NETWORK)
        end
      end

      context 'when property is set at cloud properties' do
        let(:network_name) { 'network_name' }
        let(:cloud_properties) { { 'network' => network_name } }

        context 'and its value is a network' do
          it 'should return the network name' do
            expect(networks).to receive(:get).with(network_name).and_return(network)

            expect(manager.network_name).to eql(network_name)
          end

          it 'should raise a CloudError exception if network is not found' do
            expect(networks).to receive(:get).with(network_name).and_return(nil)

            expect do
              manager.network_name
            end.to raise_error(Bosh::Clouds::CloudError, "Network `#{network_name}' not found")
          end
        end

        context 'and its value is nil' do
          let(:network_name) { nil }

          it 'should return default network' do
            expect(networks).to receive(:get).with(Bosh::Google::NetworkManager::DEFAULT_NETWORK).and_return(network)

            expect(manager.network_name).to be(Bosh::Google::NetworkManager::DEFAULT_NETWORK)
          end
        end

        context 'and its value is not a String' do
          let(:network_name) { %w(net1 net2) }

          it 'should raise a CloudError exception' do
            expect do
              manager.network_name
            end.to raise_error(Bosh::Clouds::CloudError,
                               "Invalid `network_name' property: String expected, `Array' provided")
          end
        end
      end
    end

    describe '#tags' do
      let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec) }

      context 'when property is not set at cloud properties' do
        let(:cloud_properties) { {} }

        it 'should return an empty Array' do
          expect(manager.tags).to eql([])
        end
      end

      context 'when property is set at cloud properties' do
        let(:tags) { %w(tag1 tag2) }
        let(:cloud_properties) { { 'tags' => tags } }

        context 'and its value is a list of tags' do
          it 'should return the list of tags' do
            expect(manager.tags).to eql(tags)
          end
        end

        context 'and its value is nil' do
          let(:tags) { nil }

          it 'should return an empty array' do
            expect(manager.tags).to eql([])
          end
        end

        context 'and its value is not an Array' do
          let(:tags) { 'tags' }

          it 'should raise a CloudError exception' do
            expect do
              manager.tags
            end.to raise_error(Bosh::Clouds::CloudError,
                               "Invalid `tags' property: Array expected, `String' provided")
          end
        end

        context 'and the length of any tag is greater than 63' do
          let(:tags) { ['x' * 64] }

          it 'should raise a CloudError exception' do
            expect do
              manager.tags
            end.to raise_error(Bosh::Clouds::CloudError,
                               "Invalid tag `#{tags.first}': does not comply with RFC1035")
          end
        end

        context 'and any tag does not start with a letter' do
          let(:tags) { ['1tag'] }

          it 'should raise a CloudError exception' do
            expect do
              manager.tags
            end.to raise_error(Bosh::Clouds::CloudError,
                               "Invalid tag `#{tags.first}': does not comply with RFC1035")
          end
        end

        context 'and any tag does not end with a letter or number' do
          let(:tags) { ['tag-'] }

          it 'should raise a CloudError exception' do
            expect do
              manager.tags
            end.to raise_error(Bosh::Clouds::CloudError,
                               "Invalid tag `#{tags.first}': does not comply with RFC1035")
          end
        end
      end
    end

    describe '#ephemeral_external_ip' do
      let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec) }

      context 'when property is not set at cloud properties' do
        let(:cloud_properties) { {} }

        it 'should return false' do
          expect(manager.ephemeral_external_ip).to be_falsey
        end
      end

      context 'when property is set at cloud properties' do
        let(:cloud_properties) { { 'ephemeral_external_ip' => ephemeral_external_ip } }

        context 'and its value is true' do
          let(:ephemeral_external_ip) { true }

          it 'should return true' do
            expect(manager.ephemeral_external_ip).to be_truthy
          end
        end

        context 'and its value is false' do
          let(:ephemeral_external_ip) { false }

          it 'should return false' do
            expect(manager.ephemeral_external_ip).to be_falsey
          end
        end

        context 'and its value is nil' do
          let(:ephemeral_external_ip) { nil }

          it 'should return false' do
            expect(manager.ephemeral_external_ip).to be_falsey
          end
        end

        context 'and its value is not a Boolean' do
          let(:ephemeral_external_ip) { 'ephemeral_external_ip' }

          it 'should raise a CloudError exception' do
            expect do
              manager.ephemeral_external_ip
            end.to raise_error(Bosh::Clouds::CloudError,
                               "Invalid `ephemeral_external_ip' property: Boolean expected, `String' provided")
          end
        end
      end
    end

    describe '#ip_forwarding' do
      let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec) }

      context 'when property is not set at cloud properties' do
        let(:cloud_properties) { {} }

        it 'should return false' do
          expect(manager.ip_forwarding).to be_falsey
        end
      end

      context 'when property is set at cloud properties' do
        let(:cloud_properties) { { 'ip_forwarding' => ip_forwarding } }

        context 'and its value is true' do
          let(:ip_forwarding) { true }

          it 'should return true' do
            expect(manager.ip_forwarding).to be_truthy
          end
        end

        context 'and its value is false' do
          let(:ip_forwarding) { false }

          it 'should return false' do
            expect(manager.ip_forwarding).to be_falsey
          end
        end

        context 'and its value is nil' do
          let(:ip_forwarding) { nil }

          it 'should return false' do
            expect(manager.ip_forwarding).to be_falsey
          end
        end

        context 'and its value is not a Boolean' do
          let(:ip_forwarding) { 'ip_forwarding' }

          it 'should raise a CloudError exception' do
            expect do
              manager.ip_forwarding
            end.to raise_error(Bosh::Clouds::CloudError,
                               "Invalid `ip_forwarding' property: Boolean expected, `String' provided")
          end
        end
      end
    end

    describe '#target_pool' do
      let(:manager) { subject.new(compute_api, 'dynamic' => dynamic_network_spec) }

      context 'when property is not set at cloud properties' do
        let(:cloud_properties) { {} }

        it 'should return nil' do
          expect(manager.target_pool).to be_nil
        end
      end

      context 'when property is set at cloud properties' do
        let(:target_pool_name) { 'target-pool' }
        let(:cloud_properties) { { 'target_pool' => target_pool_name } }

        context 'and its value is a target pool' do
          let(:target_pool) { double(Fog::Compute::Google::TargetPool) }

          before do
            expect(compute_api).to receive(:target_pools).and_return(target_pools)
          end

          it 'should return the target pool' do
            expect(target_pools).to receive(:get).with(target_pool_name).and_return(target_pool)

            expect(manager.target_pool).to eql(target_pool)
          end

          it 'should raise a CloudError exception if target pool is not found' do
            expect(target_pools).to receive(:get).with(target_pool_name).and_return(nil)

            expect do
              manager.target_pool
            end.to raise_error(Bosh::Clouds::CloudError, "Target Pool `#{target_pool_name}' not found")
          end
        end

        context 'and its value is nil' do
          let(:target_pool_name) { nil }

          it 'should return nil' do
            expect(manager.target_pool).to be_nil
          end
        end

        context 'and its value is not a String' do
          let(:target_pool_name) { %w(tp1 tp2) }

          it 'should raise a CloudError exception' do
            expect do
              manager.target_pool
            end.to raise_error(Bosh::Clouds::CloudError,
                               "Invalid `target_pool' property: String expected, `Array' provided")
          end
        end
      end
    end
  end
end
