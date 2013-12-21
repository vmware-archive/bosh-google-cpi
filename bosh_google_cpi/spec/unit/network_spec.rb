# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe Network do
    let(:subject) { described_class }

    let(:name) { 'network' }
    let(:spec) do
      {
        'type' => 'network',
        'name' => name,
        'ip' => ip,
        'cloud_properties' => cloud_properties
      }
    end
    let(:ip) { '1.2.3.4' }
    let(:cloud_properties) do
      {
        'key' => 'value'
      }
    end

    let(:compute_api) { double(Fog::Compute::Google) }
    let(:instance) { double(Fog::Compute::Google::Server) }

    describe '#new' do
      it 'should set attribute readers' do
        network = subject.new(name, spec)

        expect(network.name).to eql(name)
        expect(network.spec).to eql(spec)
        expect(network.ip).to eql(ip)
        expect(network.cloud_properties).to eql(cloud_properties)
      end

      context 'with invalid spec' do
        let(:spec) { 'invalid-spec' }

        it 'should raise a CloudError exception' do
          expect do
            subject.new(name, spec)
          end.to raise_error(Bosh::Clouds::CloudError, "Invalid network spec: Hash expected, `String' provided")
        end
      end

      context 'with invalid cloud properties' do
        let(:cloud_properties) { 'invalid property' }

        it 'should raise a CloudError exception' do
          expect do
            subject.new(name, spec)
          end.to raise_error(Bosh::Clouds::CloudError, "Invalid cloud properties: Hash expected, `String' provided")
        end
      end
    end

    describe '#configure' do
      let(:network) { subject.new(name, spec) }

      it 'should raise a CloudError exception' do
        expect do
          network.configure(compute_api, instance)
        end.to raise_error(Bosh::Clouds::CloudError, "`configure' not implemented by `Bosh::Google::Network'")
      end
    end
  end
end
