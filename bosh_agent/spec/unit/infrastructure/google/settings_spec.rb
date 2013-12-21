# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.
require 'spec_helper'

Bosh::Agent::Infrastructure.new('google').infrastructure

describe Bosh::Agent::Infrastructure::Google::Settings do
  let(:subject) { described_class.new }
  let(:registry) { Bosh::Agent::Infrastructure::Google::Registry }

  describe :load_settings do
    let(:settings) do
      {
        vm: { id: 'instance-identity' },
        agent_id: 'agent-id',
        networks: { default: { type: 'dynamic' } },
        disks: { system: '/dev/sda', persistent: {} }
      }
    end

    it 'should load settings' do
      registry.should_receive(:get_settings).and_return(settings)

      expect(subject.load_settings).to eql(settings)
    end
  end

  describe :get_network_settings do
    let(:network_info) do
      double('net_info', default_gateway_interface: 'eth0', default_gateway: '10.0.0.1',
                         primary_dns: '1.1.1.1', secondary_dns: '2.2.2.2')
    end

    it 'should get network settings for dynamic networks' do
      expect(Bosh::Agent::Util).to receive(:get_network_info).and_return(network_info)

      expect(subject.get_network_settings('default', { 'type' => 'dynamic' })).to eql(network_info)
    end

    it 'should do nothing for vip networks' do
      expect(Bosh::Agent::Util).to_not receive(:get_network_info)

      expect(subject.get_network_settings('default', { 'type' => 'vip' })).to be_nil
    end

    it 'should raise a StateError exception when network is not supported' do
      expect do
        subject.get_network_settings('default', { 'type' => 'unknown' })
      end.to raise_error(Bosh::Agent::StateError, /Unsupported network type 'unknown'/)
    end

    it 'should raise a StateError exception when network type is not set' do
      expect do
        subject.get_network_settings('default', {})
      end.to raise_error(Bosh::Agent::StateError, /Unsupported network type 'manual'/)
    end
  end
end
