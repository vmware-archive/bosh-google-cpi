# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'

module Bosh::Google
  describe DynamicNetwork do
    let(:subject) { described_class.new(name, spec) }

    let(:name) { 'dynamic-network' }
    let(:spec) do
      {
        'type' => 'dynamic',
        'name' => name
      }
    end

    let(:compute_api) { double(Fog::Compute::Google) }
    let(:instance) { double(Fog::Compute::Google::Server) }

    describe '#configure' do
      it 'should do nothing' do
        subject.configure(compute_api, instance)
      end
    end
  end
end
