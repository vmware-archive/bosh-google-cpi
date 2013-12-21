# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.
require File.expand_path('../../../spec/shared_spec_helper', __FILE__)

require 'cloud/google'
require 'fog/google/models/compute/addresses'
require 'fog/google/models/compute/disks'
require 'fog/google/models/compute/flavors'
require 'fog/google/models/compute/images'
require 'fog/google/models/compute/networks'
require 'fog/google/models/compute/operations'
require 'fog/google/models/compute/servers'
require 'fog/google/models/compute/snapshots'
require 'fog/google/models/compute/target_pools'
require 'fog/google/models/compute/zones'
require 'fog/google/models/storage/directories'
require 'fog/google/models/storage/files'

Dir[File.expand_path('./support/*', File.dirname(__FILE__))].each do |support_file|
  require support_file
end

def asset(filename)
  File.join(File.dirname(__FILE__), 'assets', filename)
end

RSpec.configure do |config|
  config.run_all_when_everything_filtered = true
  config.filter_run :focus

  config.order = 'random'

  config.before(:each) do
    allow(Bosh::Clouds::Config).to receive(:logger).and_return(double.as_null_object)
  end
end
