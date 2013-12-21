# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'fog'

module Bosh::Deployer
  describe Config do
    let(:config_dir) { Dir.mktmpdir('bdc_spec') }
    let(:config_google) { spec_asset('test-bootstrap-config-google.yml') }
    let(:config) { Psych.load_file(config_google) }
    let(:compute_api) { double(Fog::Compute::Google) }
    let(:storage_api) { double(Fog::Storage::Google) }

    before do
      config['dir'] = config_dir
      Fog::Compute.stub(:new).and_return(compute_api)
      Fog::Storage.stub(:new).and_return(storage_api)
    end

    after do
      FileUtils.remove_entry_secure config_dir
    end

    it 'should default agent properties' do
      Bosh::Deployer::Config.configure(config)

      properties = Bosh::Deployer::Config.cloud_options['properties']
      expect(properties['agent']).to be_kind_of(Hash)
      expect(properties['agent']['mbus'].start_with?('https://')).to be_truthy
      expect(properties['agent']['blobstore']).to be_kind_of(Hash)
    end

    it 'should map network properties' do
      Bosh::Deployer::Config.configure(config)

      networks = Bosh::Deployer::Config.networks
      expect(networks).to be_kind_of(Hash)

      net = networks['bosh']
      expect(net).to be_kind_of(Hash)
      %w(cloud_properties type).each do |key|
        expect(net[key]).to_not be_nil
      end
    end

    it 'should default vm env properties' do
      env = Bosh::Deployer::Config.env

      expect(env).to be_kind_of(Hash)
      expect(env).to have_key('bosh')
      expect(env['bosh']).to be_kind_of(Hash)
      expect(env['bosh']['password']).to_not be_nil
      expect(env['bosh']['password']).to be_kind_of(String)
      expect(env['bosh']['password']).to eql('$6$salt$password')
    end

    it 'should contain default vm resource properties' do
      Bosh::Deployer::Config.configure('dir' => config_dir, 'cloud' => { 'plugin' => 'google' })
      resources = Bosh::Deployer::Config.resources

      expect(resources).to be_kind_of(Hash)
      expect(resources['persistent_disk']).to be_kind_of(Integer)
      cloud_properties = resources['cloud_properties']
      expect(cloud_properties).to be_kind_of(Hash)
      %w(instance_type).each do |key|
        expect(cloud_properties[key]).to_not be_nil
      end
    end

    it 'should have compute_api and storage_api object access' do
      Bosh::Deployer::Config.configure(config)

      cloud = Bosh::Deployer::Config.cloud
      expect(cloud.compute_api).to eql(compute_api)
      expect(cloud.storage_api).to eql(storage_api)
    end
  end
end
