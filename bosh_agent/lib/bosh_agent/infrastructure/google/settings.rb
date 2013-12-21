# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Agent
  ##
  # BOSH Agent settings for Infrastructure Google Compute Engine
  #
  class Infrastructure::Google::Settings

    DHCP_NETWORK_TYPE       = 'dynamic'
    MANUAL_NETWORK_TYPE     = 'manual'
    VIP_NETWORK_TYPE        = 'vip'
    SUPPORTED_NETWORK_TYPES = [DHCP_NETWORK_TYPE, VIP_NETWORK_TYPE]

    ##
    # Returns the logger
    #
    # @return [Logger] BOSH Agent logger
    def logger
      Bosh::Agent::Config.logger
    end

    ##
    # Loads the the settings for this agent
    #
    # @return [Hash] Agent Settings
    def load_settings
      Infrastructure::Google::Registry.get_settings
    end

    ##
    # Gets the network settings for this agent
    #
    # @param [String] network_name Network name
    # @param [Hash] network_properties Network properties
    # @return [Hash] Network info
    # @raise [Bosh::Agent::StateError] if network type is not supported
    def get_network_settings(network_name, network_properties)
      type = network_properties['type'] || 'manual'
      unless SUPPORTED_NETWORK_TYPES.include?(type)
        raise Bosh::Agent::StateError,
              "Unsupported network type '#{type}', valid types are: #{SUPPORTED_NETWORK_TYPES.join(', ')}"
      end

      # Nothing to do for "vip" and "manual" networks
      return nil if [VIP_NETWORK_TYPE, MANUAL_NETWORK_TYPE].include? type

      Bosh::Agent::Util.get_network_info
    end
  end
end
