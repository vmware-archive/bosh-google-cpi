# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe ResourceWaitManager do
    let(:subject) { described_class.new(resource) }
    let(:task_checkpoint_delegator) { double('task_checkpoint_delegator') }

    let(:instance_identity) { 'instance-identity' }
    let(:resource) { double(Fog::Compute::Google::Server, identity: instance_identity) }
    let(:description) { "mock `#{instance_identity}'" }

    let(:max_tries) { 2 }
    let(:max_sleep_exponent) { 3 }
    let(:retry_options) do
      {
        max_tries: max_tries,
        max_sleep_exponent: max_sleep_exponent
      }
    end

    before do
      allow(Kernel).to receive(:sleep)
      allow(Bosh::Clouds::Config).to receive(:task_checkpoint).and_return(task_checkpoint_delegator)
    end

    describe '#self.wait_for' do
      let(:rwm) { double(Bosh::Google::ResourceWaitManager) }

      it 'should wait for the resource' do
        expect(described_class).to receive(:new).with(resource).and_return(rwm)
        expect(rwm).to receive(:wait_for).with(retry_options)

        described_class.wait_for(resource, retry_options)
      end
    end

    describe '#new' do
      it 'should set attribute readers' do
        expect(subject.resource).to eql(resource)
        expect(subject.description).to eql(description)
      end
    end

    describe '#wait_for' do
      it 'should set attribute readers' do
        allow(Bosh::Common).to receive(:retryable)

        subject.wait_for(retry_options)
        expect(subject.max_tries).to eql(max_tries)
        expect(subject.max_sleep_exponent).to eql(max_sleep_exponent)
      end

      it 'should return when resource is ready' do
        expect(resource).to receive(:reload).and_return(resource)
        expect(resource).to receive(:ready?).and_return(true)

        subject.wait_for(retry_options)
      end

      it 'should raise a CloudError when timeouts reaching target state' do
        expect(resource).to receive(:reload).twice.and_return(resource)
        expect(resource).to receive(:ready?).twice.and_return(false)

        expect do
          subject.wait_for(retry_options)
        end.to raise_error(Bosh::Clouds::CloudError, /Timed out waiting for #{description}/)
      end

      it 'should raise a CloudError exception when resource is not found' do
        expect(resource).to receive(:reload).and_return(nil)

        expect do
          subject.wait_for(retry_options)
        end.to raise_error(Bosh::Clouds::CloudError, "#{description} not found")
      end

      it 'should raise a CloudError exception when resource returns an error' do
        expect(resource).to receive(:reload).and_raise(Fog::Errors::Error, 'resource is already being used')

        expect do
          subject.wait_for(retry_options)
        end.to raise_error(Bosh::Clouds::CloudError,
                           "#{description} returned an error: resource is already being used")
      end

      context 'when waiting for a resource' do
        let(:max_tries) { 10 }
        let(:max_sleep_exponent) { 5 }

        it 'should wait exponentially and raise a CloudError if timeouts' do
          expect(resource).to receive(:reload).exactly(max_tries).times.and_return(resource)
          expect(resource).to receive(:ready?).exactly(max_tries).times.and_return(false)
          expect(Kernel).to receive(:rand).with(2..2).ordered.and_return(2)
          expect(Kernel).to receive(:sleep).with(2).ordered
          expect(Kernel).to receive(:rand).with(2..4).ordered.and_return(4)
          expect(Kernel).to receive(:sleep).with(4).ordered
          expect(Kernel).to receive(:rand).with(2..8).ordered.and_return(8)
          expect(Kernel).to receive(:sleep).with(8).ordered
          expect(Kernel).to receive(:rand).with(2..16).ordered.and_return(16)
          expect(Kernel).to receive(:sleep).with(16).ordered
          expect(Kernel).to receive(:rand).with(2..32).ordered.exactly(max_tries - 5).and_return(32)
          expect(Kernel).to receive(:sleep).exactly(max_tries - 5).with(32).ordered

          expect do
            subject.wait_for(retry_options)
          end.to raise_error(Bosh::Clouds::CloudError, /Timed out waiting for #{description}/)
        end
      end
    end
  end
end
