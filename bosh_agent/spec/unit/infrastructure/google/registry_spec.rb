# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.
require 'spec_helper'

Bosh::Agent::Infrastructure.new('google').infrastructure

describe Bosh::Agent::Infrastructure::Google::Registry do
  let(:subject) { described_class }
  let(:registry_schema) { 'http' }
  let(:registry_hostname) { 'registry_endpoint' }
  let(:registry_port) { '25777' }
  let(:registry_endpoint) { "#{registry_schema}://#{registry_hostname}:#{registry_port}" }
  let(:vm_id) { 'vm-id' }
  let(:nameservers) { nil }
  let(:user_data) do
    {
      registry: { endpoint: registry_endpoint },
      instance: { name: vm_id },
      dns: { nameserver: nameservers },
    }
  end
  let(:registry_settings) do
    {
      'instance' => { 'name' => vm_id },
      'agent_id' => 'agent-id',
      'networks' => { 'default' => { 'type' => 'dynamic' } },
      'disks' => { 'system' => '/dev/xvda', 'persistent' => {} }
    }
  end
  let(:metadata_uri) { 'http://169.254.169.254/computeMetadata/v1/instance/attributes/user_data' }
  let(:registry_uri) { "#{registry_endpoint}/instances/#{vm_id}/settings" }
  let(:httpclient) { double(HTTPClient) }
  let(:status) { 200 }
  let(:headers) {
    {
      'Accept' => 'application/json',
      'Metadata-Flavor' => 'Google'
    }
  }
  let(:metadata_body) { Yajl::Encoder.encode(user_data) }
  let(:registry_body) { Yajl::Encoder.encode({ settings:  Yajl::Encoder.encode(registry_settings) }) }
  let(:metadata_response) { double('response', status: status, body: metadata_body) }
  let(:registry_response) { double('response', status: status, body: registry_body) }

  describe '#get_settings' do
    before do
      allow(HTTPClient).to receive(:new).and_return(httpclient)
      allow(httpclient).to receive(:send_timeout=)
      allow(httpclient).to receive(:receive_timeout=)
      allow(httpclient).to receive(:connect_timeout=)
    end

    it 'should get agent settings' do
      expect(httpclient).to receive(:get).twice.with(metadata_uri, {}, headers).and_return(metadata_response)
      expect(httpclient).to receive(:get).with(registry_uri, {}, headers).and_return(registry_response)

      expect(subject.get_settings).to eql(registry_settings)
    end

    context 'without registry settings Hash' do
      let(:registry_body) { Yajl::Encoder.encode({ sezzings: '' }) }

      it 'should raise a LoadSettingsError exception' do
        expect(httpclient).to receive(:get).twice.with(metadata_uri, {}, headers).and_return(metadata_response)
        expect(httpclient).to receive(:get).with(registry_uri, {}, headers).and_return(registry_response)

        expect do
          subject.get_settings
        end.to raise_error(Bosh::Agent::LoadSettingsError, /Invalid response received from BOSH registry/)
      end
    end

    context 'with invalid registry settings Hash' do
      let(:registry_body) { Yajl::Encoder.encode({ settings: registry_settings }) }

      it 'should raise a LoadSettingsError exception' do
        expect(httpclient).to receive(:get).twice.with(metadata_uri, {}, headers).and_return(metadata_response)
        expect(httpclient).to receive(:get).with(registry_uri, {}, headers).and_return(registry_response)

        expect do
          subject.get_settings
        end.to raise_error(Bosh::Agent::LoadSettingsError, /Cannot parse data/)
      end
    end

    context 'when user data does not contain registry endpoint' do
      let(:user_data) { {} }

      it 'should raise a LoadSettingsError exception' do
        expect(httpclient).to receive(:get).with(metadata_uri, {}, headers).and_return(metadata_response)

        expect do
          subject.get_settings
        end.to raise_error(Bosh::Agent::LoadSettingsError, 'Cannot get BOSH registry endpoint from user data')
      end
    end

    context 'when user data does not contain instance name' do
      let(:user_data) { { registry: { endpoint: registry_endpoint } } }

      it 'should raise a LoadSettingsError exception' do
        expect(httpclient).to receive(:get).twice.with(metadata_uri, {}, headers).and_return(metadata_response)

        expect do
          subject.get_settings
        end.to raise_error(Bosh::Agent::LoadSettingsError, 'Cannot get instance name from user data')
      end
    end

    context 'when user data cannot be parsed' do
      let(:metadata_body) { user_data }

      it 'should raise a LoadSettingsError' do
        expect(httpclient).to receive(:get).with(metadata_uri, {}, headers).and_return(metadata_response)

        expect do
          subject.get_settings
        end.to raise_error(Bosh::Agent::LoadSettingsError, /Cannot parse data/)
      end
    end

    context 'when metadata server responses with an error' do
      let(:status) { 400 }

      it 'should raise a LoadSettingsError' do
        expect(httpclient).to receive(:get).with(metadata_uri, {}, headers).and_return(metadata_response)

        expect do
          subject.get_settings
        end.to raise_error(Bosh::Agent::LoadSettingsError, /returned HTTP/)
      end
    end

    context 'when metadata server call raises an Exception' do
      it 'should raise a LoadSettingsError' do
        expect(httpclient).to receive(:get).with(metadata_uri, {}, headers).and_raise(HTTPClient::TimeoutError)

        expect do
          subject.get_settings
        end.to raise_error(Bosh::Agent::LoadSettingsError, /Error requesting endpoint/)
      end
    end

    context 'with dns' do
      let(:nameservers) { ['8.8.8.8'] }
      let(:resolver) { double(Resolv::DNS) }
      let(:registry_ipaddress) { '1.2.3.4' }

      before do
        allow(Resolv::DNS).to receive(:new).with(nameserver: nameservers).and_return(resolver)
      end

      context 'when registry endpoint is a hostname' do
        let(:registry_uri) { "#{registry_schema}://#{registry_ipaddress}:#{registry_port}/instances/#{vm_id}/settings" }

        it 'should get agent settings' do
          expect(httpclient).to receive(:get).twice.with(metadata_uri, {}, headers).and_return(metadata_response)
          expect(resolver).to receive(:getaddress).with(registry_hostname).and_return(registry_ipaddress)
          expect(httpclient).to receive(:get).with(registry_uri, {}, headers).and_return(registry_response)

          expect(subject.get_settings).to eql(registry_settings)
        end

        it 'should raise a LoadSettingsError exception if can not resolve the hostname' do
          expect(httpclient).to receive(:get).with(metadata_uri, {}, headers).and_return(metadata_response)
          expect(resolver).to receive(:getaddress).with(registry_hostname).and_raise(Resolv::ResolvError)

          expect do
            subject.get_settings
          end.to raise_error(Bosh::Agent::LoadSettingsError, /Cannot lookup registry_endpoint using/)
        end
      end

      context 'when registry endpoint is an IP address' do
        let(:registry_hostname) { '1.2.3.4' }

        it 'should get agent settings' do
          expect(httpclient).to receive(:get).twice.with(metadata_uri, {}, headers).and_return(metadata_response)
          expect(resolver).to_not receive(:getaddress)
          expect(httpclient).to receive(:get).with(registry_uri, {}, headers).and_return(registry_response)

          expect(subject.get_settings).to eql(registry_settings)
        end
      end
    end
  end
end
