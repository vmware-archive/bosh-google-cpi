# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe Helpers do
    include Helpers

    describe '#cloud_error' do
      let(:logger) { double(Logger) }
      let(:error_message) { 'error message' }
      let(:error_exception) { 'error exception' }

      context 'when there is a logger' do
        before do
          @logger = logger
        end

        it 'should raise a CloudError exception and log the error and exception message' do
          expect(logger).to receive(:error).with(error_message)
          expect(logger).to receive(:error).with(error_exception)

          expect do
            cloud_error(error_message, error_exception)
          end.to raise_error(Bosh::Clouds::CloudError, error_message)
        end
      end

      context 'when there is no logger' do
        before do
          @logger = nil
        end

        it 'should raise a CloudError exception' do
          expect(logger).to_not receive(:error)

          expect do
            cloud_error(error_message, error_exception)
          end.to raise_error(Bosh::Clouds::CloudError, error_message)
        end
      end
    end

    describe '#generate_unique_name' do
      let(:unique_name) { SecureRandom.uuid }

      it 'should generate a unique name' do
        allow(SecureRandom).to receive(:uuid).and_return(unique_name)

        expect(generate_unique_name).to eql(unique_name)
      end
    end

    describe '#task_checkpoint' do
      let(:task_checkpoint_delegator) { double('task_checkpoint_delegator') }

      it 'should return the delegator' do
        allow(Bosh::Clouds::Config).to receive(:task_checkpoint).and_return(task_checkpoint_delegator)

        expect(task_checkpoint).to eql(task_checkpoint_delegator)
      end
    end

    describe '#get_name_from_resource' do
      let(:resource_name) { 'resource-name' }

      context 'when resource is a url' do
        let(:resource) { "https://api/compute/#{resource_name}" }

        it 'should return the name' do
          expect(get_name_from_resource(resource)).to eql(resource_name)
        end
      end

      context 'when resource is not a url' do
        let(:resource) { resource_name }

        it 'should return the name' do
          expect(get_name_from_resource(resource)).to eql(resource_name)
        end
      end
    end

    describe '#convert_mib_to_gib' do
      it 'should return GiB' do
        expect(convert_mib_to_gib(1024)).to eql(1)
      end

      it 'should return the ceilest GiB' do
        expect(convert_mib_to_gib(1025)).to eql(2)
      end
    end
  end
end
