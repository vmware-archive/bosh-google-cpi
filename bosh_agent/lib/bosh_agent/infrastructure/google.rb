# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Agent
  ##
  # BOSH Agent Google Compute Engine Infrastructure
  #
  class Infrastructure::Google
    require 'bosh_agent/infrastructure/google/settings'
    require 'bosh_agent/infrastructure/google/registry'

    def load_settings
      Settings.new.load_settings
    end

    def get_network_settings(network_name, properties)
      Settings.new.get_network_settings(network_name, properties)
    end
  end
end
