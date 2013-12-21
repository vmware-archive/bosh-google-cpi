# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'tempfile'
require 'bosh/dev/google/micro_bosh_deployment_manifest'
require 'psych'

module Bosh::Dev::Google
  describe MicroBoshDeploymentManifest do
    subject { described_class.new(env) }
    let(:env) { {} }

    it 'is writable' do
      expect(subject).to be_a(Bosh::Dev::WritableManifest)
    end

    its(:filename) { should eq('micro_bosh.yml') }

    describe '#to_h' do
      let(:expected_yml) { <<YAML }
---
name: microbosh-google-jenkins

logging:
  level: DEBUG

network:
  type: dynamic
  vip: vip
  cloud_properties:
    tags:
      - bosh

resources:
  persistent_disk: 4096
  cloud_properties:
    instance_type: n1-standard-2

cloud:
  plugin: google
  properties:
    google:
      project: project
      client_email: client_email
      pkcs12_key: ''
      default_zone: zone
      access_key_id: access_key_id
      secret_access_key: secret_access_key
      private_key: private_key_path

    registry:
      endpoint: http://admin:admin@localhost:25889
      user: admin
      password: admin

apply_spec:
  properties: { }
YAML

      before do
        env.merge!(
          'BOSH_GOOGLE_MICROBOSH_IP' => 'vip',
          'BOSH_GOOGLE_PROJECT' => 'project',
          'BOSH_GOOGLE_CLIENT_EMAIL' => 'client_email',
          'BOSH_GOOGLE_PKCS12_KEY_FILE' => Tempfile.new('pkcs12'),
          'BOSH_GOOGLE_DEFAULT_ZONE' => 'zone',
          'BOSH_GOOGLE_ACCESS_KEY_ID' => 'access_key_id',
          'BOSH_GOOGLE_SECRET_ACCESS_KEY' => 'secret_access_key',
          'BOSH_GOOGLE_PRIVATE_KEY' => 'private_key_path'
        )
      end

      it 'generates the correct YAML' do
        expect(subject.to_h).to eq(Psych.load(expected_yml))
      end
    end
  end
end
