# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'rspec'
require 'yaml'
require 'common/properties'
require 'json'

describe 'registry.yml.erb' do
  let(:deployment_manifest_fragment) do
    {
      'properties' => {
        'registry' => {
          'http' => {
            'port' => 'port',
            'user' => 'user',
            'password' => 'password'
          },
          'db' => {
            'adapter' => 'mysql2',
            'user' => 'ub45391e00',
            'password' => 'p4cd567d84d0e012e9258d2da30',
            'host' => 'bosh.hamazonhws.com',
            'port' => 3306,
            'database' => 'bosh',
            'connection_options' => {}
          }
        }
      }
    }
  end

  let(:erb_yaml) do
    erb_yaml_path = File.join(File.dirname(__FILE__), '../jobs/registry/templates/registry.yml.erb')

    File.read(erb_yaml_path)
  end

  context 'google' do
    let(:google_properties) {
      {
        'project' => 'cloud-project',
        'client_email' => 'email@developer.gserviceaccount.com',
        'pkcs12_key' => 'pkcs12-key',
      }
    }
    let(:spec) { deployment_manifest_fragment }
    let(:rendered_yaml) { ERB.new(erb_yaml).result(Bosh::Common::TemplateEvaluationContext.new(spec).get_binding) }
    let(:parsed) { YAML.load(rendered_yaml) }

    before do
      deployment_manifest_fragment['properties']['google'] = google_properties
    end

    it 'renders plugin correctly' do
      expect(parsed['cloud']['plugin']).to eq('google')
    end

    it 'renders google properties correctly' do
      expect(parsed['cloud']['google']).to eq(google_properties)
    end
  end
end
