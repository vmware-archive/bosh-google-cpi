# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'bosh/dev/google/bat_deployment_manifest'
require 'bosh/stemcell/archive'
require 'psych'
require 'bosh/dev/bat/director_uuid'
require 'bosh/stemcell/archive'

module Bosh::Dev::Google
  describe BatDeploymentManifest do
    subject { described_class.new(env, director_uuid, stemcell_archive) }
    let(:env) { {} }
    let(:director_uuid) { instance_double('Bosh::Dev::Bat::DirectorUuid', value: 'director-uuid') }
    let(:stemcell_archive) { instance_double('Bosh::Stemcell::Archive', version: 13, name: 'stemcell-name') }

    its(:filename) { should eq ('bat.yml') }

    it 'is writable' do
      expect(subject).to be_a(Bosh::Dev::WritableManifest)
    end

    describe '#to_h' do
      let(:expected_yml) { <<YAML }
---
cpi: google
properties:
  uuid: director-uuid
  static_ip: vip
  pool_size: 1
  stemcell:
    name: stemcell-name
    version: 13
  instances: 1
  mbus: nats://nats:0b450ada9f830085e2cdeff6@vip:4222
  network:
    type: dynamic
    cloud_properties:
      tags: ['bosh']
YAML

      before do
        env.merge!(
            'BOSH_GOOGLE_BAT_IP' => 'vip'
        )
      end

      it 'generates the correct YAML' do
        expect(subject.to_h).to eq(Psych.load(expected_yml))
      end
    end
  end
end
