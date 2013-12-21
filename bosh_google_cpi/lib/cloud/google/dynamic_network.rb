# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # Google Compute Engine Dynamic Network Abstraction
  #
  class DynamicNetwork < Network
    ##
    # Creates a new Google Compute Engine Dynamic Network
    #
    # @param [String] name Network name
    # @param [Hash] spec Network spec
    # @return [Bosh::Google:DynamicNetwork] Google Compute Engine Dynamic Network
    def initialize(name, spec)
      super
    end

    ##
    # Configures the Dynamic Network
    #
    # @param [Fog::Compute::Google] compute_api Fog Google Compute Engine client
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def configure(compute_api, instance)
      # This is a no-op, as dynamic networks are completely managed by Google Compute Engine
    end
  end
end
