# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # Manages Google Compute Engine Instances
  #
  class InstanceManager
    include Helpers

    MAX_METADATA_KEY_LENGTH   = 128
    MAX_METADATA_VALUE_LENGTH = 32_768

    attr_reader :logger
    attr_reader :compute_api

    ##
    # Creates a new Google Compute Engine Instance Manager
    #
    # @param [Fog::Compute::Google] compute_api Fog Google Compute Engine client
    # @return [Bosh::Google::InstanceManager] Google Compute Engine Instance Manager
    def initialize(compute_api)
      @logger = Bosh::Clouds::Config.logger
      @compute_api = compute_api
    end

    ##
    # Returns an existing Google Compute Engine instance
    #
    # @param [String] identity Google Compute Engine instance identity
    # @return [Fog::Compute::Google::Server] Google Compute Engine instance
    # @raise [Bosh::Clouds::VMNotFound] if Google Compute Engine instance is not found
    def get(identity)
      instance = compute_api.servers.get(identity)
      unless instance
        logger.error("Instance `#{identity}' not found")
        raise Bosh::Clouds::VMNotFound
      end

      instance
    end

    ##
    # Creates a new Google Compute Engine instance
    #
    # @param [String] zone Google Compute Engine zone
    # @param [Fog::Compute::Google::Image] image Google Compute Engine image
    # @param [Hash] resource_pool Cloud specific properties describing the resources needed for this instance
    # @param [Bosh::Google::NetworkManager] network_manager Google Compute Engine network manager
    # @param [String] registry_endpoint BOSH Registry endpoint URI
    # @return [Fog::Compute::Google::Server] Google Compute Engine instance
    # @raise [Bosh::Clouds::VMCreationFailed] if failed to create the Google Compute Engine instance
    def create(zone, image, resource_pool, network_manager, registry_endpoint)
      params = create_params("vm-#{generate_unique_name}", zone, image, resource_pool,
                             network_manager, registry_endpoint)
      logger.debug("Using boot params: `#{params.inspect}'")
      instance = compute_api.servers.create(params)

      logger.debug("Creating new vm `#{instance.identity}'...")
      begin
        ResourceWaitManager.wait_for(instance)
      rescue Bosh::Clouds::CloudError
        raise Bosh::Clouds::VMCreationFailed.new(true)
      end

      instance.reload
    end

    ##
    # Terminates an existing Google Compute Engine instance
    #
    # @param [String] identity Google Compute Engine instance identity
    # @return [void]
    def terminate(identity)
      instance = get(identity)

      operation = instance.destroy
      ResourceWaitManager.wait_for(operation)
    end

    ##
    # Reboots an existing Google Compute Engine instance
    #
    # @param [String] identity Google Compute Engine instance id
    # @return [void]
    def reboot(identity)
      instance = get(identity)

      operation = instance.reboot
      ResourceWaitManager.wait_for(operation)
    end

    ##
    # Checks if a Google Compute Engine instance exists
    #
    # @param [String] identity Google Compute Engine instance identity
    # @return [Boolean] True if the Google Compute Engine instance exists, false otherwise
    def exists?(identity)
      get(identity)
      true
    rescue Bosh::Clouds::VMNotFound
      false
    end

    ##
    # Set metadata for an existing Google Compute Engine instance
    #
    # @param [String] identity Google Compute Engine instance identity
    # @param [Hash] metadata Metadata key/value pairs to add to the Google Compute Engine instance
    # @return [void]
    def set_metadata(identity, metadata)
      return if metadata.nil? || metadata.empty?

      instance = get(identity)

      # We need to reuse the current instance metadata, as there are some fields, like user-data, that are used
      # to pass arbitrary data to the vm
      instance_metadata = {}
      instance.metadata.fetch('items', []).each { |i| instance_metadata[i['key']] = i['value'] }

      metadata.each do |key, value|
        trimmed_key = key[0..(MAX_METADATA_KEY_LENGTH - 1)]
        trimmed_value = value[0..(MAX_METADATA_VALUE_LENGTH - 1)]
        instance_metadata[trimmed_key] = trimmed_value
      end

      operation = instance.set_metadata(instance_metadata)
      ResourceWaitManager.wait_for(operation)
    end

    ##
    # Attaches an existing Google Compute Engine disk to an existing Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @param [Fog::Compute::Google::Disk] disk Google Compute Engine disk
    # @return [String] device name
    # @raise [Bosh::Clouds::CloudError] if unable to attach Google Compute Engine to the Google Compute Engine instance
    def attach_disk(instance, disk)
      operation = instance.attach_disk(disk.self_link, writable: true)
      ResourceWaitManager.wait_for(operation)

      instance.reload
      attachment = instance.disks.find { |d| d['source'] == disk.self_link }
      cloud_error("Unable to attach disk `#{disk.identity}' to vm `#{instance.identity}'") unless attachment

      attachment['deviceName']
    end

    ##
    # Detaches an existing Google Compute Engine disk from an existing Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Server] instance Google Compute Engine instance
    # @param [Fog::Compute::Google::Disk] disk Google Compute Engine disk
    # @return [void]
    # @raise [Bosh::Clouds::DiskNotAttached] if Google Compute Engine disk is not attached to the Google
    # Compute Engine instance
    def detach_disk(instance, disk)
      attachment = instance.disks.find { |d| d['source'] == disk.self_link }
      unless attachment
        logger.error("Disk `#{disk.identity}' is not attached to vm `#{instance.identity}'")
        raise Bosh::Clouds::DiskNotAttached.new(true)
      end

      operation = instance.detach_disk(attachment['deviceName'])
      ResourceWaitManager.wait_for(operation)
    end

    ##
    # List the attached Google Compute Engine disks of an existing Google Compute Engine instance
    #
    # @param [String] identity Google Compute Engine instance identity
    # @return [Array<String>] List of disk identities attached to the instance
    def attached_disks(identity)
      instance = get(identity)

      attached_disks = instance.disks.reject { |d| d['boot'] == true }

      attached_disks.map { |d| get_name_from_resource(d['source']) }
    end

    private

    ##
    # Returns the params to be used to boot a new Google Compute Engine instance
    #
    # @param [String] name Instance name
    # @param [String] zone Google Compute Engine zone
    # @param [Fog::Compute::Google::Image] image Google Compute Engine image
    # @param [Hash] resource_pool Cloud specific properties describing the resources needed for this instance
    # @param [Bosh::Google::NetworkManager] network_manager Google Compute Engine network manager
    # @param [String] registry_endpoint BOSH Registry endpoint URI
    # @return [Hash] Instance boot params
    def create_params(name, zone, image, resource_pool, network_manager, registry_endpoint)
      params = {
        name: name,
        zone: zone,
        description: 'Instance managed by BOSH',
        machine_type: get_machine_type(resource_pool['instance_type'], zone),
        disks: build_boot_disk(image),
        metadata: build_user_data(name, registry_endpoint, network_manager),
        auto_restart: get_automatic_restart(resource_pool['automatic_restart']),
        on_host_maintenance: get_on_host_maintenance(resource_pool['on_host_maintenance']),
        service_accounts: get_service_scopes(resource_pool['service_scopes'])
      }

      params.merge!(get_network_conf(network_manager))

      params
    end

    ##
    # Returns the Google Compute Engine machine type to be used to boot a new Google Compute Engine instance
    #
    # @param [String] name Google Compute Engine machine type name
    # @param [String] zone Google Compute Engine zone
    # @return [String] Google Compute Engine machine type self link
    # @raise [Bosh::Clouds::CloudError] if Google Compute Engine machine type name is not found
    def get_machine_type(name, zone)
      cloud_error("Missing `instance_type' param at resource pool cloud properties") if name.nil?

      machine_type = compute_api.flavors.get(name, zone)
      cloud_error("Machine Type `#{name}' not found") if machine_type.nil?

      logger.debug("Using Machine Type: `#{name}' (`#{machine_type.description}')")
      name
    end

    ##
    # Returns the Google Compute Engine disk options to be used to boot a new Google Compute Engine instance
    #
    # @param [Fog::Compute::Google::Image] image Google Compute Engine image
    # @return [Array<Hash>] Google Compute Engine disk to boot the Google Compute Engine instance
    def build_boot_disk(image)
      [{
        'boot' => true,
        'type' => 'PERSISTENT',
        'autoDelete' => true,
        'initializeParams' => { 'sourceImage' => image.self_link }
      }]
    end

    ##
    # Returns the user data to be injected onto the Google Compute Engine instance
    #
    # @param [String] name Google Compute Engine instance name
    # @param [String] registry_endpoint BOSH Registry endpoint URI
    # @param [Bosh::Google::NetworkManager] network_manager Google Compute Engine network manager
    # @return [Hash] User data to be injected onto the Google Compute Engine instance
    def build_user_data(name, registry_endpoint, network_manager)
      user_data = {
        'instance' => { 'name' => name },
        'registry' => { 'endpoint' => registry_endpoint }
      }

      dns_list = network_manager.dns
      user_data['dns'] = { 'nameserver' => dns_list } if dns_list.any?

      logger.debug("Setting user data: `#{user_data}'")
      { 'user_data' => Yajl::Encoder.encode(user_data) }
    end

    ##
    # Returns if the instance should be restarted automatically if it is terminated for non-user-initiated reasons
    # (maintenance event, hardware failure, software failure, etc). By default we set this value to false as it can
    # interfere with the 'Resurrector' Bosh Health Monitor plugin.
    #
    # @param [Boolean] automatic_restart Instance should be automatically restarted?
    # @return [Boolean] true if instance should be automatically restarted; false otherwise
    # @raise [Bosh::Clouds::CloudError] if automatic_restart property is not valid
    def get_automatic_restart(automatic_restart)
      automatic_restart = false if automatic_restart.nil?
      unless automatic_restart.is_a?(TrueClass) || automatic_restart.is_a?(FalseClass)
        cloud_error("Invalid `automatic_restart' property: Boolean expected, `#{automatic_restart.class}' provided")
      end

      automatic_restart
    end

    ##
    # Returns the instance behavior on infrastructure maintenance that may temporarily impact instance performance.
    # Supported values are 'MIGRATE' (default) or 'TERMINATE'.
    #
    # @param [String] on_host_maintenance Instance behavior on infrastructure maintenance
    # @return [String] Instance behavior on infrastructure maintenance
    # @raise [Bosh::Clouds::CloudError] if on_host_maintenance property is not valid
    def get_on_host_maintenance(on_host_maintenance)
      on_host_maintenance = 'MIGRATE' if on_host_maintenance.nil?
      unless on_host_maintenance.is_a?(String)
        cloud_error("Invalid `on_host_maintenance' property: String expected, `#{on_host_maintenance.class}' provided")
      end
      unless %w(MIGRATE TERMINATE).include?(on_host_maintenance.upcase)
        cloud_error("Invalid `on_host_maintenance' property: only `MIGRATE' or `TERMINATE' are supported")
      end

      on_host_maintenance.upcase
    end

    ##
    # Returns the instance service account scopes to access other Google services
    #
    # @param [String] service_scopes Service account scopes
    # @return [String] Instance service account scopes
    # @raise [Bosh::Clouds::CloudError] if service_scopes property is not valid
    def get_service_scopes(service_scopes)
      service_scopes = [] if service_scopes.nil?

      unless service_scopes.is_a?(Array)
        cloud_error("Invalid `service_scopes' property: Array expected, `#{service_scopes.class}' provided")
      end

      service_scopes.empty? ? nil : service_scopes
    end

    ##
    # Returns the network configuration to be used to boot a new Google Compute Engine instance
    #
    # @param [Bosh::Google::NetworkManager] network_manager Google Compute Engine network manager
    # @return [Hash] Network configuration to be used to boot a new Google Compute Engine instance
    def get_network_conf(network_manager)
      network_conf = {}

      network_conf[:network] = network_manager.network_name if network_manager.network_name
      network_conf[:tags] = network_manager.tags
      network_conf[:external_ip] = false if network_manager.ephemeral_external_ip == false
      network_conf[:can_ip_forward] = network_manager.ip_forwarding

      logger.debug("Using network configuration: #{network_conf.inspect}") unless network_conf.empty?
      network_conf
    end
  end
end
