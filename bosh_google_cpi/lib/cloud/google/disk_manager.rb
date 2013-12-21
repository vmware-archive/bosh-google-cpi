# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # Manages Google Compute Engine Disks
  #
  class DiskManager
    include Helpers

    attr_reader :logger
    attr_reader :compute_api

    ##
    # Creates a new Google Compute Engine Disk Manager
    #
    # @param [Fog::Compute::Google] compute_api Fog Google Compute Engine client
    # @return [Bosh::Google::DiskManager] Google Compute Engine Disk Manager
    def initialize(compute_api)
      @logger = Bosh::Clouds::Config.logger
      @compute_api = compute_api
    end

    ##
    # Returns an existing Google Compute Engine disk
    #
    # @param [String] identity Google Compute Engine disk identity
    # @return [Fog::Compute::Google::Disk] Google Compute Engine disk
    # @raise [Bosh::Clouds::DiskNotFound] if Google Compute Engine disk is not found
    def get(identity)
      disk = compute_api.disks.get(identity)
      unless disk
        logger.error("Disk `#{identity}' not found")
        raise Bosh::Clouds::DiskNotFound.new(true)
      end

      disk
    end

    ##
    # Creates a new blank Google Compute Engine disk
    #
    # @param [Integer] size Google Compute Engine disk size in MiB
    # @param [String] zone Google Compute Engine zone
    # @return [Fog::Compute::Google::Disk] Google Compute Engine disk
    # @raise [Bosh::Clouds::CloudError] if disk size is not valid
    def create_blank(size, zone)
      cloud_error('Disk size needs to be an Integer') unless size.kind_of?(Integer)

      size_gb = convert_mib_to_gib(size)
      cloud_error("Minimum disk size is 1 GiB and you set #{size_gb} GiB") if size_gb < 1
      cloud_error("Maximum disk size is 10 TiB and you set #{size_gb} GiB") if size_gb > 10_000

      params = create_params("disk-#{generate_unique_name}", zone, size: size_gb)
      create_disk(params)
    end

    ##
    # Creates a new Google Compute Engine disk from a Google Compute Engine image
    #
    # @param [Fog::Compute::Google::Image] image Google Compute Engine image
    # @param [String] zone Google Compute Engine zone
    # @return [Fog::Compute::Google::Disk] Google Compute Engine disk
    # @raise [Bosh::Clouds::CloudError] if image is not valid
    def create_from_image(image, zone)
      params = create_params("disk-#{generate_unique_name}", zone, image: image)
      create_disk(params)
    end

    ##
    # Deletes an existing Google Compute Engine disk
    #
    # @param [String] identity Google Compute Engine disk identity
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if Google Compute Engine disk is not in a ready state
    def delete(identity)
      disk = get(identity)

      cloud_error("Cannot delete disk `#{identity}', status is `#{disk.status}'") unless disk.ready?

      operation = disk.destroy
      ResourceWaitManager.wait_for(operation)
    end

    private

    ##
    # Returns the params to be used to create a new Google Compute Engine disk
    #
    # @param [String] name Disk name
    # @param [String] zone Google Compute Engine zone
    # @param [optional, Hash] options Google Compute Engine disk options
    # @option [Integer] size Disk size in GiB
    # @option [Fog::Compute::Google::Image] image Google Compute Engine image
    # @return [Hash] Google Compute Engine disk create params
    # @raise [Bosh::Clouds::CloudError] if disk options are not valid
    def create_params(name, zone, options = {})
      params = {
        name: name,
        zone: zone,
        description: 'Disk managed by BOSH'
      }

      size = options.delete(:size)
      image = options.delete(:image)
      cloud_error('Must specify disk size or image') if size.nil? && image.nil?

      params[:size_gb] = size if size
      params[:source_image] = image.self_link if image

      params
    end

    ##
    # Creates a new Google Compute Engine disk
    #
    # @param [Hash] params Google Compute Engine disk create params
    # @return [Fog::Compute::Google::Disk] Google Compute Engine disk
    def create_disk(params)
      logger.debug("Using disk params: `#{params.inspect}'")
      disk = compute_api.disks.create(params)

      logger.debug("Creating new disk `#{disk.identity}'...")
      ResourceWaitManager.wait_for(disk)

      disk.reload
    end
  end
end
