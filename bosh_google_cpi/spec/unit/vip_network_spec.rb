# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe VipNetwork do
    let(:subject) { described_class.new(name, spec) }

    let(:name) { 'vip-network' }
    let(:spec) do
      {
        'type' => 'vip',
        'name' => name,
        'ip' => ip
      }
    end

    let(:compute_api) { double(Fog::Compute::Google) }
    let(:instance) {
      double(Fog::Compute::Google::Server,
             identity: instance_identity,
             zone_name: instance_zone,
             public_ip_address: public_ip_address,
             network_interfaces: network_interfaces)
    }
    let(:instance_identity) { 'instance-identity' }
    let(:instance_zone) { 'instance-zone' }
    let(:public_ip_address) { nil }
    let(:network_interfaces) { [] }
    let(:addresses) { double(Fog::Compute::Google::Addresses) }
    let(:address) { double(Fog::Compute::Google::Address, in_use?: in_use) }
    let(:operations) { double(Fog::Compute::Google::Operations) }
    let(:operation) { double(Fog::Compute::Google::Operation) }

    describe '#configure' do
      context 'with ip address' do
        let(:ip) { '1.2.3.4' }

        before do
          allow(compute_api).to receive(:addresses).and_return(addresses)
        end

        context 'already assigned to the instance' do
          let(:public_ip_address) { '1.2.3.4' }

          it 'should do nothing' do
            subject.configure(compute_api, instance)
          end
        end

        context 'allocated' do
          before do
            expect(addresses).to receive(:get_by_ip_address).with(ip).and_return(address)
          end

          context 'and not in use' do
            let(:in_use) { false }

            context 'with a public IP address already assigned' do
              let(:public_ip_address) { '5.6.7.8' }
              let(:nic_name) { 'nic' }
              let(:nat_name) { 'External NAT' }
              let(:network_interfaces) { [{ 'name' => nic_name, 'accessConfigs' => [{ 'name' => nat_name }] }] }
              let(:response) { Excon::Response.new(body: { 'name' => 'name', 'zone' => 'zone' }) }

              it 'should deassociate the public IP address and associate the IP address to the instance' do
                expect(compute_api).to receive(:delete_server_access_config)
                  .with(instance_identity, instance_zone, nic_name, access_config: nat_name)
                  .and_return(response)
                expect(compute_api).to receive(:operations).and_return(operations)
                expect(operations).to receive(:get).and_return(operation)
                expect(Bosh::Google::ResourceWaitManager).to receive(:wait_for).with(operation)
                expect(address).to receive(:server=).with(instance)
                expect(instance).to receive(:reload)

                subject.configure(compute_api, instance)
              end
            end

            context 'without a public IP address already assigned' do
              it 'should associate the IP address to the instance' do
                expect(address).to receive(:server=).with(instance)
                expect(instance).to receive(:reload)

                subject.configure(compute_api, instance)
              end
            end
          end

          context 'and in use' do
            let(:in_use) { true }
            let(:instance_2) { double(Fog::Compute::Google::Server, identity: 'instance-identity-2') }

            it 'should raise a CloudError exception' do
              expect(address).to receive(:server).and_return(instance_2)

              expect do
                subject.configure(compute_api, instance)
              end.to raise_error(Bosh::Clouds::CloudError,
                                 "Static IP address `#{ip}' already in use by instance `#{instance_2.identity}'")
            end
          end
        end

        context 'not allocated' do
          it 'should raise a CloudError exception' do
            expect do
              expect(addresses).to receive(:get_by_ip_address).with(ip).and_return(nil)

              subject.configure(compute_api, instance)
            end.to raise_error(Bosh::Clouds::CloudError, "Static IP address `#{ip}' not allocated")
          end
        end
      end

      context 'without ip address' do
        let(:ip) { nil }

        it 'should raise a CloudError exception' do
          expect do
            subject.configure(compute_api, instance)
          end.to raise_error(Bosh::Clouds::CloudError, "No static IP address provided for vip network `#{name}'")
        end
      end
    end
  end
end
