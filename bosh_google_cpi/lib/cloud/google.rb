# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh
  ##
  # BOSH Google Compute Engine CPI
  #
  module Google
  end
end

require 'fog'
require 'google/api_client'
require 'json'
require 'securerandom'
require 'yajl'

require 'common/common'
require 'common/exec'
require 'common/thread_pool'
require 'common/thread_formatter'

require 'bosh/registry/client'

require 'cloud'
require 'cloud/google/version'
require 'cloud/google/helpers'
require 'cloud/google/cloud'

require 'cloud/google/network'
require 'cloud/google/dynamic_network'
require 'cloud/google/vip_network'

require 'cloud/google/disk_manager'
require 'cloud/google/disk_snapshot_manager'
require 'cloud/google/image_manager'
require 'cloud/google/instance_manager'
require 'cloud/google/network_manager'
require 'cloud/google/registry_manager'
require 'cloud/google/resource_wait_manager'

module Bosh
  ##
  # BOSH Cloud CPI
  #
  module Clouds
    Google = Bosh::Google::Cloud
  end
end
