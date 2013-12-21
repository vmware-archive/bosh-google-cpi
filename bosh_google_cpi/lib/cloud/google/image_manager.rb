# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # Manages Google Compute Engine Images
  #
  class ImageManager
    include Helpers

    attr_reader :logger
    attr_reader :compute_api
    attr_reader :storage_api

    ##
    # Creates a new Google Compute Engine Image Manager
    #
    # @param [Fog::Compute::Google] compute_api Fog Google Compute Engine client
    # @param [Fog::Storage::Google] storage_api Fog Google Cloud Storage client
    # @return [Bosh::Google::ImageManager] Google Compute Engine Image Manager
    def initialize(compute_api, storage_api)
      @logger = Bosh::Clouds::Config.logger
      @compute_api = compute_api
      @storage_api = storage_api
    end

    ##
    # Returns an existing Google Compute Engine image
    #
    # @param [String] image_identity Google Compute Engine image image_identity
    # @return [Fog::Compute::Google::Image] Google Compute Engine image
    # @raise [Bosh::Clouds::CloudError] if Google Compute Engine image is not found
    def get(image_identity)
      compute_api.images.get(image_identity)
    rescue Fog::Errors::NotFound
      cloud_error("Image `#{image_identity}' not found")
    end

    ##
    # Creates a new Google Compute Engine image from a remote location
    #
    # @param [String] source_url Google Cloud Storage URL where the disk image is stored
    # @param [String] description Description of the Google Compute Engine image
    # @return [Fog::Compute::Google::Image] Google Compute Engine image
    def create_from_url(url, description)
      name = "stemcell-#{generate_unique_name}"
      logger.debug("Using remote image located at `#{url}'")
      create(name, description, url)
    end

    ##
    # Creates a new Google Compute Engine image from a tarball
    #
    # @param [String] image_path Local filesystem path to a stemcell image
    # @param [String] description Description of the Google Compute Engine image
    # @return [Fog::Compute::Google::Image] Google Compute Engine image
    def create_from_tarball(image_path, description)
      name = "stemcell-#{generate_unique_name}"
      logger.debug("Creating Google Cloud Storage bucket `#{name}'")
      bucket = storage_api.directories.create(key: name, acl: 'private')

      file_name = "#{name}.tar.gz"
      logger.debug("Uploading image `#{file_name}' to Google Cloud Storage bucket `#{name}'")
      file = bucket.files.create(key: file_name, body: File.open(image_path, 'r'), acl: 'public-read')

      create(name, description, file.public_url)
    ensure
      file.destroy if file
      bucket.destroy if bucket
    end

    ##
    # Deletes an existing Google Compute Engine image
    #
    # @param [String] image_identity Google Compute Engine image identity
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if Google Compute Engine image is not in a ready state
    def delete(image_identity)
      image = get(image_identity)

      cloud_error("Cannot delete image `#{image_identity}', status is `#{image.status}'") unless image.ready?

      operation = image.destroy
      ResourceWaitManager.wait_for(operation)
    end

    private

    ##
    # Creates a new Google Compute Engine image
    #
    # @param [String] name Name of the Google Compute Engine image
    # @param [String] description Description of the Google Compute Engine image
    # @param [String] source_url Google Cloud Storage URL where the disk image is stored
    # @return [Fog::Compute::Google::Image] Google Compute Engine image
    def create(name, description, source_url)
      params = create_params(name, description, source_url)
      logger.debug("Using image params: `#{params.inspect}'")
      image = compute_api.images.create(params)

      logger.debug("Creating new image `#{image.identity}'...")
      ResourceWaitManager.wait_for(image)

      image.reload
    end

    ##
    # Returns the params to be used to create a new Google Compute Engine image
    #
    # @param [String] name Name of the Google Compute Engine image
    # @param [String] description Description of the Google Compute Engine image
    # @param [String] source_url Google Cloud Storage URL where the disk image is stored
    # @return [Hash] Google Compute Engine image create params
    def create_params(name, description, source_url)
      {
        name: name,
        description: description,
        raw_disk: source_url
      }
    end
  end
end
