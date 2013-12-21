# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved..

module Bosh::Google
  ##
  # Manages Google Compute Engine networks
  #
  class NetworkManager
    include Helpers

    MAX_TAG_LENGTH = 63
    DEFAULT_NETWORK = 'default'

    attr_reader :logger
    attr_reader :compute_api
    attr_reader :dynamic_network
    attr_reader :vip_network

    ##
    # Creates a new Google Compute Engine Network Manager
    #
    # @param [Fog::Compute::Google] compute_api Fog Google Compute Engine client
    # @param [Hash] raw_network_spec Raw network spec
    # @return [Bosh::Google::NetworkManager] Google Compute Engine Network Manager
    def initialize(compute_api, raw_network_spec)
      @logger = Bosh::Clouds::Config.logger
      @compute_api = compute_api

      @dynamic_network = nil
      @vip_network = nil

      parse_network_spec(raw_network_spec)
    end

    ##
    # Applies a network configuration to a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def configure(instance)
      configure_dynamic_network(instance)
      configure_vip_network(instance)
      configure_target_pool(instance)
    end

    ##
    # Updates a network configuration for a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def update(instance)
      configure(instance)
      update_network(instance)
      update_ephemeral_external_ip(instance)
      update_ip_forwarding(instance)
      update_tags(instance)
    end

    ##
    # Returns the DNS server list to use in a Google Compute Engine instance
    #
    # @return [Array<String>] DNS server list
    # @raise [Bosh::Clouds::CloudError] if dns set at network spec are not valid
    def dns
      dns = dynamic_network.spec.fetch('dns', []) || []

      cloud_error("Invalid `dns' property: Array expected, `#{dns.class}' provided") unless dns.is_a?(Array)

      dns
    end

    ##
    # Returns the Google Compute Engine network name to use in a Google Compute Engine instance
    #
    # @return [String] Google Compute Engine network name
    # @raise [Bosh::Clouds::CloudError] if network property set at cloud_properties is not valid
    def network_name
      network_name = dynamic_network.cloud_properties['network'] || DEFAULT_NETWORK

      unless network_name.is_a?(String)
        cloud_error("Invalid `network_name' property: String expected, `#{network_name.class}' provided")
      end

      network = compute_api.networks.get(network_name)
      cloud_error("Network `#{network_name}' not found") if network.nil?

      network_name
    end

    ##
    # Returns the list of tags to use in a Google Compute Engine instance
    #
    # @return [Array<String>] List of tags
    # @raise [Bosh::Clouds::CloudError] if tags set at cloud_properties are not valid
    def tags
      tags = dynamic_network.cloud_properties.fetch('tags', []) || []

      cloud_error("Invalid `tags' property: Array expected, `#{tags.class}' provided") unless tags.is_a?(Array)

      tags.each do |tag|
        if tag.size > MAX_TAG_LENGTH || !tag.match('^[A-Za-z]+[A-Za-z0-9-]*[A-Za-z0-9]+$')
          cloud_error("Invalid tag `#{tag}': does not comply with RFC1035")
        end
      end

      tags
    end

    ##
    # Returns if the Google Compute Engine instance should have an ephemeral external ip address
    #
    # @return [Boolean] true if the instance should have an ephemeral external ip address; false otherwise
    # @raise [Bosh::Clouds::CloudError] if ephemeral_external_ip property set at cloud_properties is not valid
    def ephemeral_external_ip
      ephemeral_external_ip = dynamic_network.cloud_properties.fetch('ephemeral_external_ip', false) || false
      unless ephemeral_external_ip.is_a?(TrueClass) || ephemeral_external_ip.is_a?(FalseClass)
        cloud_error("Invalid `ephemeral_external_ip' property: Boolean expected, " \
                    "`#{ephemeral_external_ip.class}' provided")
      end

      ephemeral_external_ip
    end

    ##
    # Returns if the Google Compute Engine instance should do ip forwarding
    #
    # @return [Boolean] true if the instance should do ip forwarding; false otherwise
    # @raise [Bosh::Clouds::CloudError] if ip_forwarding property set at cloud_properties is not valid
    def ip_forwarding
      ip_forwarding = dynamic_network.cloud_properties.fetch('ip_forwarding', false) || false
      unless ip_forwarding.is_a?(TrueClass) || ip_forwarding.is_a?(FalseClass)
        cloud_error("Invalid `ip_forwarding' property: Boolean expected, `#{ip_forwarding.class}' provided")
      end

      ip_forwarding
    end

    ##
    # Returns the Google Compute Engine target pool to use in a Google Compute Engine instance
    #
    # @return [Fog::Compute::Google::TargetPool] Google Compute Engine target pool
    # @raise [Bosh::Clouds::CloudError] if target_pool property set at cloud_properties is not valid
    def target_pool
      target_pool_name = dynamic_network.cloud_properties['target_pool'] || nil
      return nil if target_pool_name.nil?

      unless target_pool_name.is_a?(String)
        cloud_error("Invalid `target_pool' property: String expected, `#{target_pool_name.class}' provided")
      end

      target_pool = compute_api.target_pools.get(target_pool_name)
      cloud_error("Target Pool `#{target_pool_name}' not found") if target_pool.nil?

      target_pool
    end

    private

    ##
    # Parses the network spec
    #
    # @param [Hash] raw_network_spec Raw network spec
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if network spec is invalid
    def parse_network_spec(raw_network_spec)
      unless raw_network_spec.is_a?(Hash)
        cloud_error("Invalid network spec: Hash expected, `#{raw_network_spec.class}' provided")
      end

      raw_network_spec.each_pair { |name, spec| parse_network(name, spec) }

      cloud_error("At least one `dynamic' network should be defined") unless dynamic_network
    end

    ##
    # Parses a network
    #
    # @param [String] name Network name
    # @param [Hash] spec Network spec
    # @return[void]
    # @raise [Bosh::Clouds::CloudError] if network spec is invalid
    def parse_network(name, spec)
      network_type = spec['type']

      case network_type
        when 'dynamic'
          cloud_error("Must have exactly one `dynamic' network per instance") if dynamic_network
          @dynamic_network = DynamicNetwork.new(name, spec)

        when 'vip'
          cloud_error("Must have exactly one `vip' network per instance") if vip_network
          @vip_network = VipNetwork.new(name, spec)

        else
          cloud_error("Invalid network type `#{network_type}': only `dynamic' and 'vip' are supported")
      end
    end

    ##
    # Configures the dynamic network for a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def configure_dynamic_network(instance)
      dynamic_network.configure(compute_api, instance)
    end

    ##
    # Configures the vip network for a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def configure_vip_network(instance)
      if vip_network
        vip_network.configure(compute_api, instance)
      else
        if ip = instance.public_ip_address
          if address = compute_api.addresses.get_by_ip_address(ip)
            logger.debug("Disassociating static IP address `#{ip}' from instance `#{instance.identity}'")
            address.server = nil
            instance.reload
          end
        end
      end
    end

    ##
    # Add a Google Compute Engine instance to a Google Compute Engine target pool
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return[void]
    # @raise [Bosh::Clouds::CloudError] if Google Compute Engine target pool is not found
    def configure_target_pool(instance)
      if tp = target_pool
        return if tp.instances && tp.instances.include?(instance.self_link)

        logger.debug("Adding Instance `#{instance.identity}' to Target Pool `#{tp.identity}'")
        tp.add_instance(instance)
      else
        # TODO: Check if instance has a target pool associated and dissasociate it
      end
    end

    ##
    # Updates the network for a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    # @raise [Bosh::Clouds:NotSupported] If the network has changed, we need to recreate the VM
    # as we can not change the network of a running instance, so we need to send the InstanceUpdater
    # a request to do it for us
    def update_network(instance)
      instance_network_name = get_name_from_resource(instance.network_interfaces.first['network'])
      if instance_network_name != network_name
        raise Bosh::Clouds::NotSupported,
              "Network change requires VM recreation: `#{instance_network_name}' to `#{network_name}'"
      end
    end

    ##
    # Updates the ephemeral external IP for a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def update_ephemeral_external_ip(instance)
      instance_external_ip = instance.public_ip_address
      if ephemeral_external_ip
        associate_ephemeral_ip(instance) unless instance_external_ip
      elsif instance_external_ip
        deassociate_ephemeral_ip(instance) unless compute_api.addresses.get_by_ip_address(instance_external_ip)
      end
    end

    ##
    # Associates an ephemeral external IP to a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def associate_ephemeral_ip(instance)
      logger.debug("Associating ephemeral IP address to instance `#{instance.identity}'")
      data = compute_api.add_server_access_config(instance.identity,
                                                  instance.zone_name,
                                                  instance.network_interfaces.first['name'])

      operation = compute_api.operations.get(data.body['name'], data.body['zone'])
      ResourceWaitManager.wait_for(operation)
    end

    ##
    # Deassociates an ephemeral external IP from a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def deassociate_ephemeral_ip(instance)
      logger.debug("Disassociating ephemeral IP address from instance `#{instance.identity}'")
      access_config = instance.network_interfaces.first['accessConfigs'].first['name']
      data = compute_api.delete_server_access_config(instance.identity,
                                                     instance.zone_name,
                                                     instance.network_interfaces.first['name'],
                                                     access_config: access_config)
      operation = compute_api.operations.get(data.body['name'], data.body['zone'])
      ResourceWaitManager.wait_for(operation)
    end

    ##
    # Updates the IP forwarding for a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    # @raise [Bosh::Clouds:NotSupported] If IP forwarding has changed, we need to recreate the VM
    # as we can not change the network of a running instance, so we need to send the InstanceUpdater
    # a request to do it for us
    def update_ip_forwarding(instance)
      instance_ip_forwarding = instance.can_ip_forward
      if instance_ip_forwarding != ip_forwarding
        raise Bosh::Clouds::NotSupported,
              "IP forwarding change requires VM recreation: `#{instance_ip_forwarding}' to `#{ip_forwarding}'"
      end
    end

    ##
    # Updates tags for a Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @return [void]
    def update_tags(instance)
      instance_tags = instance.tags.fetch('items', [])
      if instance_tags.sort != tags.sort
        logger.debug("Setting tags `#{tags.join(', ')}' to instance `#{instance.identity}'")
        operation = instance.set_tags(tags)
        ResourceWaitManager.wait_for(operation)
      end
    end
  end
end
