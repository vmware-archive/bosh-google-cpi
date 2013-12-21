# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe RegistryManager do
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
    let(:subject) { described_class.new(registry_options) }
    let(:instance_identity) { 'instance-identity' }
    let(:settings) { { 'vm' => { 'id' => instance_identity } } }
    let(:max_tries) { Bosh::Google::RegistryManager::MAX_TRIES }

    let(:task_checkpoint_delegator) { double('task_checkpoint_delegator') }
    let(:registry) { double(Bosh::Registry::Client) }

    before do
      allow(Kernel).to receive(:sleep)
      allow(Bosh::Clouds::Config).to receive(:task_checkpoint).and_return(task_checkpoint_delegator)
      allow(Bosh::Registry::Client).to receive(:new)
                                       .with(registry_endpoint, registry_user, registry_password)
                                       .and_return(registry)
    end

    describe '#new' do
      it 'should set attribute readers' do
        expect(subject.registry).to eql(registry)
      end
    end

    describe '#read' do
      it 'should return instance settings' do
        expect(registry).to receive(:read_settings).with(instance_identity).and_return(settings)

        expect(subject.read(instance_identity)).to eql(settings)
      end

      context 'when there is an expected exception' do
        it 'should retry' do
          expect(registry).to receive(:read_settings).with(instance_identity)
            .and_raise(HTTPClient::ConnectTimeoutError)
          expect(registry).to receive(:read_settings).with(instance_identity).and_return(settings)

          expect(subject.read(instance_identity)).to eql(settings)
        end
      end

      context 'when timeouts' do
        it 'should raise a CloudError' do
          expect(registry).to receive(:read_settings).with(instance_identity).exactly(max_tries)
            .and_raise(HTTPClient::ConnectTimeoutError)

          expect do
            subject.read(instance_identity)
          end.to raise_error(Bosh::Clouds::CloudError, 'Timed out waiting for BOSH Registry')
        end
      end
    end

    describe '#update' do
      it 'should update instance settings' do
        expect(registry).to receive(:update_settings).with(instance_identity, settings).and_return(true)

        subject.update(instance_identity, settings)
      end

      context 'when there is an expected exception' do
        it 'should retry' do
          expect(registry).to receive(:update_settings).with(instance_identity, settings)
            .and_raise(HTTPClient::ConnectTimeoutError)
          expect(registry).to receive(:update_settings).with(instance_identity, settings).and_return(true)

          subject.update(instance_identity, settings)
        end
      end

      context 'when timeouts' do
        it 'should raise a CloudError' do
          expect(registry).to receive(:update_settings).with(instance_identity, settings).exactly(max_tries)
            .and_raise(HTTPClient::ConnectTimeoutError)

          expect do
            subject.update(instance_identity, settings)
          end.to raise_error(Bosh::Clouds::CloudError, 'Timed out waiting for BOSH Registry')
        end
      end
    end

    describe '#delete' do
      it 'should delete instance settings' do
        expect(registry).to receive(:delete_settings).with(instance_identity).and_return(true)

        subject.delete(instance_identity)
      end

      context 'when there is an expected exception' do
        it 'should retry' do
          expect(registry).to receive(:delete_settings).with(instance_identity)
                              .and_raise(HTTPClient::ConnectTimeoutError)
          expect(registry).to receive(:delete_settings).with(instance_identity).and_return(true)

          subject.delete(instance_identity)
        end
      end

      context 'when timeouts' do
        it 'should raise a CloudError' do
          expect(registry).to receive(:delete_settings).with(instance_identity).exactly(max_tries)
            .and_raise(HTTPClient::ConnectTimeoutError)

          expect do
            subject.delete(instance_identity)
          end.to raise_error(Bosh::Clouds::CloudError, 'Timed out waiting for BOSH Registry')
        end
      end
    end
  end
end
