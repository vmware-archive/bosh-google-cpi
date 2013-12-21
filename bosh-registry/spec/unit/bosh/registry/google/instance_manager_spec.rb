# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'bosh/registry/instance_manager/google'
require 'fog/google/models/compute/servers'

module Bosh::Registry
  describe InstanceManager::Google do
    let(:subject) { described_class }
    let(:config) { valid_config }

    before do
      config['cloud'] = {
        'plugin' => 'google',
        'google' => {
          'project'      => 'cloud-project',
          'client_email' => 'email@developer.gserviceaccount.com',
          'pkcs12_key'   => 'pkcs12-key'
        }
      }
    end

    describe '#new' do
      it 'validates presence of cloud option' do
        config['cloud'].delete('google')

        expect do
          subject.new(config['cloud'])
        end.to raise_error(Bosh::Registry::ConfigError, /Missing configuration parameters: google/)
      end

      it 'validates presence of google project' do
        config['cloud']['google'].delete('project')

        expect do
          subject.new(config['cloud'])
        end.to raise_error(Bosh::Registry::ConfigError, /Missing configuration parameters: google:project/)
      end

      it 'validates presence of google client email' do
        config['cloud']['google'].delete('client_email')

        expect do
          subject.new(config['cloud'])
        end.to raise_error(Bosh::Registry::ConfigError, /Missing configuration parameters: google:client_email/)
      end

      it 'validates presence of google pkcs12 key' do
        config['cloud']['google'].delete('pkcs12_key')

        expect do
          subject.new(config['cloud'])
        end.to raise_error(Bosh::Registry::ConfigError, /Missing configuration parameters: google:pkcs12_key/)
      end
    end

    describe '#instance_ips' do
      let(:manager) { subject.new(config['cloud']) }
      let(:compute_api) { double(Fog::Compute::Google) }
      let(:instances) { double(Fog::Compute::Google::Servers) }
      let(:instance_identity) { 'instance-identity' }
      let(:instance) { double(Fog::Compute::Google::Server, identity: instance_identity) }
      let(:private_ip_address) { '10.177.18.209' }
      let(:public_ip_address) { '166.78.105.63' }

      before do
        Fog::Compute.stub(:new).and_return(compute_api)
        compute_api.stub(:servers).and_return(instances)
      end

      it 'should return the instance private ips' do
        instances.should_receive(:get).with(instance_identity).and_return(instance)
        instance.should_receive(:addresses).and_return([private_ip_address])

        ips = manager.instance_ips(instance_identity)
        expect(ips).to include private_ip_address
        expect(ips).to_not include public_ip_address
      end

      it 'should return the instance public ips' do
        instances.should_receive(:get).with(instance_identity).and_return(instance)
        instance.should_receive(:addresses).and_return([public_ip_address])

        ips = manager.instance_ips(instance_identity)
        expect(ips).to_not include private_ip_address
        expect(ips).to include public_ip_address
      end

      it 'should return the instance public and private ips' do
        instances.should_receive(:get).with(instance_identity).and_return(instance)
        instance.should_receive(:addresses).and_return([private_ip_address, public_ip_address])

        ips = manager.instance_ips(instance_identity)
        expect(ips).to include private_ip_address
        expect(ips).to include public_ip_address
      end

      it 'should return an empty array if instance has no ips' do
        instances.should_receive(:get).with(instance_identity).and_return(instance)
        instance.should_receive(:addresses).and_return([])

        expect(manager.instance_ips(instance_identity)).to eql([])
      end

      it 'should raise a InstanceNotFound if instance is not found' do
        instances.should_receive(:get).with(instance_identity).and_return(nil)

        expect do
          manager.instance_ips(instance_identity)
        end.to raise_error(Bosh::Registry::InstanceNotFound, "Instance `#{instance_identity}' not found")
      end

      it 'should raise a ConnectionError if unable to connect to the Google Compute Engine API' do
        Fog::Compute.should_receive(:new).and_raise(Fog::Errors::Error)

        expect do
          manager.instance_ips(instance_identity)
        end.to raise_error(Bosh::Registry::ConnectionError, 'Unable to connect to the Google Compute Engine API')
      end
    end
  end
end
