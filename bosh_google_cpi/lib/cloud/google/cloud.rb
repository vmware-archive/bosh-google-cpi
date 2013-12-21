# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # BOSH Google Compute Engine CPI
  #
  class Cloud < Bosh::Cloud
    include Helpers

    attr_reader   :compute_api
    attr_reader   :storage_api
    attr_reader   :options
    attr_accessor :logger

    ##
    # Creates a new BOSH Google Compute Engine CPI
    #
    # @param [Hash] options CPI options (the contents of sub-hashes are defined in the {file:README.md})
    # @option options [Hash] google Google CPI options
    # @option options [Hash] agent BOSH Agent options
    # @option options [Hash] registry BOSH Registry options
    # @return [Bosh::Google::Cloud] BOSH Google Compute Engine CPI
    def initialize(options)
      @options = options.dup
      validate_options

      @logger = Bosh::Clouds::Config.logger

      initialize_compute_api_client
      initialize_storage_api_client
    end

    ##
    # Creates a new stemcell
    #
    # @param [String] image_path Local filesystem path to a stemcell image
    # @param [Hash] stemcell_properties Stemcell properties
    # @option stemcell_properties [String] infrastructure  Stemcell infrastructure
    # @option stemcell_properties [optional, String] source_url Google Cloud Storage URL where the disk image is stored
    # @return [String] BOSH stemcell id
    def create_stemcell(image_path, stemcell_properties)
      with_thread_name("create_stemcell(#{image_path}, ...)") do
        infrastructure = stemcell_properties.fetch('infrastructure', 'unknown')
        unless infrastructure && infrastructure == 'google'
          cloud_error("Invalid Google Compute Engine stemcell, infrastructure is `#{infrastructure}'")
        end

        logger.info('Creating new stemcell...')
        description = "#{stemcell_properties['name']}/#{stemcell_properties['version']}"
        if source_url = stemcell_properties.delete('source_url')
          image = image_manager.create_from_url(source_url, description)
        else
          image = image_manager.create_from_tarball(image_path, description)
        end

        image.identity.to_s
      end
    end

    ##
    # Deletes an existing stemcell
    #
    # @param [String] stemcell_id BOSH stemcell id to delete
    # @return [void]
    def delete_stemcell(stemcell_id)
      with_thread_name("delete_stemcell(#{stemcell_id})") do
        logger.info("Deleting stemcell `#{stemcell_id}'...")
        image_manager.delete(stemcell_id)
      end
    end

    ##
    # Creates a new vm
    #
    # @param [String] agent_id BOSH agent id (will be picked up by agent to assume its identity)
    # @param [String] stemcell_id BOSH stemcell id
    # @param [Hash] resource_pool Cloud specific properties describing the resources needed for this vm
    # @param [Hash] networks List of networks and their settings needed for this vm
    # @param [optional, Array<String>] disk_locality List of disks that might be attached to this instance in the
    # future, can be used as a placement hint (i.e. instance will only be created if resource pool zone is the same
    # as disk zone)
    # @param [optional, Hash] environment Data to be merged into agent settings
    # @return [String] VM id
    # rubocop:disable ParameterLists
    def create_vm(agent_id, stemcell_id, resource_pool, network_spec, disk_locality = nil, environment = nil)
      with_thread_name("create_vm(#{agent_id}, ...)") do
        zone = select_zone(disks: disk_locality, resource_pool: resource_pool['zone'])
        network_manager = network_manager(network_spec)
        image = image_manager.get(stemcell_id)

        begin
          logger.info('Creating new vm...')
          vm = instance_manager.create(zone, image, resource_pool, network_manager, registry_manager.registry.endpoint)

          logger.info("Configuring network for vm `#{vm.identity}'...")
          network_manager.configure(vm)

          logger.info("Updating agent settings for vm `#{vm.identity}'...")
          registry_manager.update(vm.identity,
                                  initial_agent_settings(vm.identity, agent_id, network_spec, environment))

          vm.identity.to_s
        rescue => e
          logger.error("Failed to create vm: #{e.inspect}")
          cleanup_failed_vm(vm)
          raise Bosh::Clouds::VMCreationFailed.new(true)
        end
      end
    end
    # rubocop:enable ParameterLists

    ##
    # Deletes an existing vm
    #
    # @param [String] vm_id VM id
    # @return [void]
    def delete_vm(vm_id)
      with_thread_name("delete_vm(#{vm_id})") do
        logger.info("Deleting vm `#{vm_id}'...")
        instance_manager.terminate(vm_id)

        logger.info("Deleting agent settings for vm `#{vm_id}'...")
        registry_manager.delete(vm_id)
      end
    end

    ##
    # Reboots an existing vm
    #
    # @param [String] vm_id VM id
    # @return [void]
    def reboot_vm(vm_id)
      with_thread_name("reboot_vm(#{vm_id})") do
        logger.info("Rebooting vm `#{vm_id}'...")
        instance_manager.reboot(vm_id)
      end
    end

    ##
    # Checks if a vm exists
    #
    # @param [String] vm_id VM id
    # @return [Boolean] True if the vm exists; false otherwise
    def has_vm?(vm_id)
      with_thread_name("has_vm?(#{vm_id})") do
        logger.info("Checking if vm `#{vm_id}' exists")
        instance_manager.exists?(vm_id)
      end
    end

    ##
    # Set metadata for an existing vm
    #
    # @param [String] vm_id VM id
    # @param [Hash] metadata Metadata key/value pairs to add to the vm
    # @return [void]
    def set_vm_metadata(vm_id, metadata)
      with_thread_name("set_vm_metadata(#{vm_id}, ...)") do
        logger.info("Setting metadata for server `#{vm_id}'")
        instance_manager.set_metadata(vm_id, metadata)
      end
    end

    ##
    # Configures networking on existing vm
    #
    # @param [String] vm_id VM id
    # @param [Hash] network_spec Raw network spec
    # @return [void]
    def configure_networks(vm_id, network_spec)
      with_thread_name("configure_networks(#{vm_id}, ...)") do
        vm = instance_manager.get(vm_id)

        logger.info("Updating network configuration for vm `#{vm_id}'...")
        network_manager = network_manager(network_spec)
        network_manager.update(vm)

        logger.info("Updating agent settings for vm `#{vm_id}'...")
        update_network_settings(vm_id, network_spec)
      end
    end

    ##
    # Creates a new disk
    #
    # @param [Integer] disk_size Disk size in MiB
    # @param [optional, String] vm_id VM id of the VM that this disk will be attached to
    # @return [String] Disk id
    def create_disk(disk_size, vm_id = nil)
      with_thread_name("create_disk(#{disk_size}, #{vm_id})") do
        logger.info('Creating new disk...')
        disk = disk_manager.create_blank(disk_size, select_zone(instances: vm_id))

        disk.identity.to_s
      end
    end

    ##
    # Deletes an existing disk
    #
    # @param [String] disk_id Disk id
    # @return [void]
    def delete_disk(disk_id)
      with_thread_name("delete_disk(#{disk_id})") do
        logger.info("Deleting disk `#{disk_id}'...")
        disk_manager.delete(disk_id)
      end
    end

    ##
    # Attaches an existing disk to an existing vm
    #
    # @param [String] vm_id VM id
    # @param [String] disk_id Disk id
    # @return [void]
    def attach_disk(vm_id, disk_id)
      with_thread_name("attach_disk(#{vm_id}, #{disk_id})") do
        vm = instance_manager.get(vm_id)
        disk = disk_manager.get(disk_id)

        logger.info("Attaching disk `#{disk_id}' to vm `#{vm_id}'...")
        device_name = instance_manager.attach_disk(vm, disk)

        logger.info("Updating agent settings for vm `#{vm_id}'...")
        update_disk_settings(vm_id, disk_id, device_name.to_s)
      end
    end

    ##
    # Detaches an existing disk from an existing vm
    #
    # @param [String] vm_id VM id
    # @param [String] disk_id Disk id
    # @return [void]
    def detach_disk(vm_id, disk_id)
      with_thread_name("detach_disk(#{vm_id}, #{disk_id})") do
        vm = instance_manager.get(vm_id)
        disk = disk_manager.get(disk_id)

        logger.info("Detaching disk `#{disk_id}' from vm `#{vm_id}'...")
        instance_manager.detach_disk(vm, disk)

        logger.info("Updating agent settings for vm `#{vm_id}'...")
        update_disk_settings(vm_id, disk_id)
      end
    end

    ##
    # List the attached disks of an existing vm
    #
    # @param [String] vm_id VM id
    # @return [Array<String>] List of disk ids attached to an existing vm
    def get_disks(vm_id)
      with_thread_name("get_disks(#{vm_id})") do
        instance_manager.attached_disks(vm_id)
      end
    end

    ##
    # Takes a snapshot of an existing disk
    #
    # @param [String] disk_id Disk id
    # @param [Hash] metadata Metadata key/value pairs to add to the disk snapshot
    # @return [String] Disk snapshot id
    def snapshot_disk(disk_id, metadata)
      with_thread_name("snapshot_disk(#{disk_id}, ...)") do
        disk = disk_manager.get(disk_id)

        logger.info("Creating new snapshot for disk `#{disk_id}'...")
        disk_snapshot = disk_snapshot_manager.create(disk, metadata)

        disk_snapshot.identity.to_s
      end
    end

    ##
    # Deletes an existing disk snapshot
    #
    # @param [String] disk_snapshot_id Disk snapshot id
    # @return [void]
    def delete_snapshot(disk_snapshot_id)
      with_thread_name("delete_snapshot(#{disk_snapshot_id})") do
        logger.info("Deleting disk snapshot `#{disk_snapshot_id}'...")
        disk_snapshot_manager.delete(disk_snapshot_id)
      end
    end

    ##
    # Validates the deployment
    #
    # @note Not implemented in this CPI
    def validate_deployment(old_manifest, new_manifest)
      not_implemented(:validate_deployment)
    end

    private

    ##
    # Creates a new Image Manager instance
    #
    # @return [Bosh::Google:ImageManager] Image Manager
    def image_manager
      @img_mgr ||= ImageManager.new(compute_api, storage_api)
    end

    ##
    # Creates a new Instance Manager instance
    #
    # @return [Bosh::Google:InstanceManager] Instance Manager
    def instance_manager
      @ins_mgr ||= InstanceManager.new(compute_api)
    end

    ##
    # Creates a new Disk Manager instance
    #
    # @return [Bosh::Google:DiskManager] Disk Manager
    def disk_manager
      @dis_mgr ||= DiskManager.new(compute_api)
    end

    ##
    # Creates a new Disk Snapshot Manager instance
    #
    # @return [Bosh::Google:DiskSnapshotManager] Disk Snapshot Manager
    def disk_snapshot_manager
      @sna_mgr ||= DiskSnapshotManager.new(compute_api)
    end

    ##
    # Creates a new Network Manager instance
    #
    # @param [Hash] network_spec Raw network spec
    # @return [Bosh::Google:NetworkManager] Network Manager
    def network_manager(network_spec)
      NetworkManager.new(compute_api, network_spec)
    end

    ##
    # Creates a new BOSH Registry Manager instance
    #
    # @return [Bosh::Google:RegistryManager] BOSH Registry Manager
    def registry_manager
      @reg_mgr ||= RegistryManager.new(registry_properties)
    end

    ##
    # Checks if options passed to CPI are valid and can actually be used to create all required data structures
    #
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if options are not valid
    def validate_options
      required_keys = {
        'google' => %w(project client_email pkcs12_key default_zone access_key_id secret_access_key),
        'registry' => %w(endpoint user password)
      }

      missing_keys = []

      required_keys.each_pair do |key, values|
        values.each do |value|
          missing_keys << "#{key}:#{value}" unless options.key?(key) && options[key].key?(value)
        end
      end

      cloud_error("Missing configuration parameters: #{missing_keys.join(', ')}") unless missing_keys.empty?
    end

    ##
    # Initialize the Fog Google Compute Engine client
    #
    # @return [Fog::Compute::Google] Fog Google Compute Engine client
    # @raise [Bosh::Clouds::CloudError] if unable to connect to the Google Compute Engine API
    def initialize_compute_api_client
      initialize_compute_api_logger

      @compute_api = Fog::Compute.new(google_compute_api_params)
    rescue Fog::Errors::Error => e
      logger.error(e)
      cloud_error('Unable to connect to the Google Compute Engine API. Check task debug log for details.')
    end

    ##
    # Initialize the Fog Google Cloud Storage client
    #
    # @return [Fog::Storage::Google] Fog Google Cloud Storage client
    # @raise [Bosh::Clouds::CloudError] if unable to connect to the Google Cloud Storage API
    def initialize_storage_api_client
      @storage_api = Fog::Storage.new(google_storage_api_params)
    rescue Fog::Errors::Error => e
      logger.error(e)
      cloud_error('Unable to connect to the Google Cloud Storage API. Check task debug log for details.')
    end

    ##
    # Initialize the Google API Logger
    #
    # @return [void]
    def initialize_compute_api_logger
      cpi_log = options['cpi_log']

      unless cpi_log.nil?
        Google::APIClient.logger = Logger.new(cpi_log)
        Google::APIClient.logger.level = logger.level
        Google::APIClient.logger.formatter = logger.formatter
      end
    end

    ##
    # Returns the Google Compute Engine properties
    #
    # @return [Hash] Google Compute Engine properties
    def google_properties
      options.fetch('google')
    end

    ##
    # Returns the Google Compute Engine connection params
    #
    # @return [Hash] Google Compute Engine connection params
    def google_compute_api_params
      {
        provider:            'Google',
        google_project:      google_properties.fetch('project'),
        google_client_email: google_properties.fetch('client_email'),
        google_key_string:   Base64.decode64(google_properties.fetch('pkcs12_key'))
      }
    end

    ##
    # Returns the Google Cloud Storage connection params
    #
    # @return [Hash] Google Cloud Storage connection params
    def google_storage_api_params
      {
        provider:                         'Google',
        google_storage_access_key_id:     google_properties.fetch('access_key_id'),
        google_storage_secret_access_key: google_properties.fetch('secret_access_key')
      }
    end

    ##
    # Returns the BOSH Registry properties
    #
    # @return [Hash] BOSH Registry properties
    def registry_properties
      options.fetch('registry', {})
    end

    ##
    # Clean up a failed vm
    #
    # @param [Fog::Compute::Google::Server] vm Google Compute Engine instance
    # @return void
    def cleanup_failed_vm(vm)
      unless vm.nil?
        logger.info("Deleting vm `#{vm.identity}'...")
        instance_manager.terminate(vm.identity)
      end
    rescue => e
      # If something goes wrong, just log the error and don't override the original exception
      logger.error("Error cleaning up vm: #{e}")
    end

    ##
    # Selects the Google Compute Engine zone to use
    #
    # @param [Hash] affinities List of affinities
    # @option affinities [String] resource_pool Resource pool zone
    # @option affinities [Array<String>] disks Google Compute Engine disk ids
    # @option affinities [Array<String>] instances Google Compute Engine instance ids
    # @return [String] Google Compute Engine zone
    # @raise [Bosh::Clouds::CloudError] if resources are on diferent Google Compute Engine zones
    def select_zone(affinities = {})
      resource_pool = Array(affinities.delete(:resource_pool))

      disks_zones = Array(affinities.delete(:disks)).map do |disk_id|
        get_name_from_resource(disk_manager.get(disk_id).zone)
      end

      instances_zones = Array(affinities.delete(:instances)).map do |vm_id|
        get_name_from_resource(instance_manager.get(vm_id).zone)
      end

      zones = (resource_pool + disks_zones + instances_zones).compact.uniq
      cloud_error("Can't use multiple zones: `#{zones.join(', ')}'") if zones.size > 1

      zones.first || default_zone
    end

    ##
    # Returns the Google Compute Engine default zone
    #
    # @return [String] Google Compute Engine default zone
    def default_zone
      google_properties.fetch('default_zone')
    end

    ##
    # Generates initial agent settings
    #
    # These settings will be read by BOSH Agent from BOSH Registry on a target server
    #
    # @param [String] vm_id VM id (will be picked up by agent to fetch registry settings)
    # @param [String] agent_id BOSH Agent ID (will be picked up by agent to assume its identity)
    # @param [Hash] network_spec Raw network spec
    # @param [Hash] environment Environment settings
    # @return [Hash] Agent settings
    def initial_agent_settings(vm_id, agent_id, network_spec, environment)
      settings = {
        'vm' => { 'id' => vm_id },
        'agent_id' => agent_id,
        'networks' => network_spec,
        'disks' => { 'system' => '/dev/sda', 'persistent' => {} }
      }

      settings['env'] = environment if environment

      settings.merge(options.fetch('agent', {}))
    end

    ##
    # Updates the agent settings
    #
    # These settings will be read by BOSH Agent from BOSH Registry on a target server
    #
    # @param [String] vm_id VM id (will be picked up by agent to fetch registry settings)
    # @yieldparam [Hash] settings New agent settings
    # @raise [ArgumentError] if block is not provided
    def update_agent_settings(vm_id)
      raise ArgumentError, 'Block is not provided' unless block_given?

      settings = registry_manager.read(vm_id)
      yield settings
      registry_manager.update(vm_id, settings)
    end

    ##
    # Update the agent disk settings
    #
    # These settings will be read by BOSH Agent from BOSH Registry on a target server
    #
    # @param [String] vm_id VM id (will be picked up by agent to fetch registry settings)
    # @param [String] disk_id Disk id
    # @param [String] device_name Device name
    # @return [void]
    def update_disk_settings(vm_id, disk_id, device_name = nil)
      update_agent_settings(vm_id) do |settings|
        settings['disks'] ||= {}
        settings['disks']['persistent'] ||= {}
        if device_name
          settings['disks']['persistent'][disk_id] = device_name
        else
          settings['disks']['persistent'].delete(disk_id)
        end
      end
    end

    ##
    # Update the agent network settings
    #
    # These settings will be read by BOSH Agent from BOSH Registry on a target server
    #
    # @param [String] vm_id VM id  (will be picked up by agent to fetch registry settings)
    # @param [Hash] network_spec Raw network spec
    # @return [void]
    def update_network_settings(vm_id, network_spec)
      update_agent_settings(vm_id) do |settings|
        settings['networks'] = network_spec
      end
    end
  end
end
