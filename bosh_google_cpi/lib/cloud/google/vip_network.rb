# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # Google Compute Engine Vip Network Abstraction
  #
  class VipNetwork < Network
    ##
    # Creates a new Google Compute Engine Vip Network
    #
    # @param [String] name Network name
    # @param [Hash] spec Network spec
    # @return [Bosh::Google:VipNetwork] Google Compute Engine Vip Network
    def initialize(name, spec)
      super
    end

    ##
    # Configures the Vip Network
    #
    # Assigns a Google Compute Engine static IP address to a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google] compute_api Fog Google Compute Engine client
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if no IP address is provided at network spec
    # @raise [Bosh::Clouds::CloudError] if Google Compute Engine static IP address does not exists
    # @raise [Bosh::Clouds::CloudError] if Google Compute Engine static IP address is already in use
    def configure(compute_api, instance)
      cloud_error("No static IP address provided for vip network `#{name}'") unless ip

      return if instance.public_ip_address == ip

      address = compute_api.addresses.get_by_ip_address(ip)
      cloud_error("Static IP address `#{ip}' not allocated") unless address

      if address.in_use?
        cloud_error("Static IP address `#{ip}' already in use by instance `#{address.server.identity}'")
      end

      deassociate_ip(compute_api, instance) if public_ip = instance.public_ip_address

      logger.debug("Associating static IP address `#{ip}' to instance `#{instance.identity}'")
      address.server = instance
      instance.reload
    end

    ##
    # Deassociates an external IP from a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google] compute_api Fog Google Compute Engine client
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def deassociate_ip(compute_api, instance)
      logger.debug("Disassociating IP address `#{instance.public_ip_address}' from instance `#{instance.identity}'")
      access_config = instance.network_interfaces.first['accessConfigs'].first['name']
      data = compute_api.delete_server_access_config(instance.identity,
                                                     instance.zone_name,
                                                     instance.network_interfaces.first['name'],
                                                     access_config: access_config)
      operation = compute_api.operations.get(data.body['name'], data.body['zone'])
      ResourceWaitManager.wait_for(operation)
    end
  end
end
