# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # Google Compute Engine Network Abstraction
  #
  class Network
    include Helpers

    attr_reader :logger
    attr_reader :name
    attr_reader :spec
    attr_reader :ip
    attr_reader :cloud_properties

    ##
    # Creates a new Google Compute Engine Network
    #
    # @param [String] name Network name
    # @param [Hash] spec Network spec
    # @return [Bosh::Google:Network] Google Compute Engine Network
    def initialize(name, spec)
      @logger = Bosh::Clouds::Config.logger

      cloud_error("Invalid network spec: Hash expected, `#{spec.class}' provided") unless spec.is_a?(Hash)

      @name = name
      @spec = spec
      @ip = spec['ip']
      @cloud_properties = spec.fetch('cloud_properties', {})
      unless cloud_properties.is_a?(Hash)
        cloud_error("Invalid cloud properties: Hash expected, `#{cloud_properties.class}' provided")
      end
    end

    ##
    # Configures the Network
    #
    # @param [Fog::Compute::Google] compute_api Fog Google Compute Engine client
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def configure(compute_api, instance)
      cloud_error("`configure' not implemented by `#{self.class}'")
    end
  end
end
