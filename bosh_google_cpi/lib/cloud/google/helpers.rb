# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # BOSH Google Compute Engine CPI Helpers
  #
  module Helpers
    ##
    # Raises a CloudError exception
    #
    # @param [String] message Message about what went wrong
    # @param [optional, Exception] exception Exception to be logged
    # @raise [Bosh::Clouds::CloudError]
    def cloud_error(message, exception = nil)
      @logger.error(message) if @logger
      @logger.error(exception) if @logger && exception
      raise Bosh::Clouds::CloudError, message
    end

    ##
    # Generates an unique name
    #
    # @return [String] Unique name
    def generate_unique_name
      SecureRandom.uuid
    end

    ##
    # Checks if the invoker's task has been cancelled
    #
    # @note This method uses a delegator defined at Bosh::Clouds::Config
    def task_checkpoint
      Bosh::Clouds::Config.task_checkpoint
    end

    ##
    # Returns the resource name from a resource
    #
    # @param [String] Resource
    # @return [String] Resource name
    def get_name_from_resource(resource)
      resource.split('/').last
    end

    ##
    # Converts a size from MiB to GiB
    #
    # @param [Integer] size Size in MiB
    # @return [Integer] Size in GiB
    def convert_mib_to_gib(size)
      (size / 1024.0).ceil
    end
  end
end
