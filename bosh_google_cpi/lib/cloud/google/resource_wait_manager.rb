# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # Manages Resources Waits
  #
  class ResourceWaitManager
    include Helpers

    DEFAULT_MAX_TRIES          = 100 # Default maximum number of retries
    DEFAULT_MAX_SLEEP_EXPONENT =   3 # Default maximum sleep exponent before retrying a call

    attr_reader :logger
    attr_reader :resource
    attr_reader :description

    attr_reader :max_tries
    attr_reader :max_sleep_exponent
    attr_reader :started_at

    def self.wait_for(resource, options = {})
      ResourceWaitManager.new(resource).wait_for(options)
    end

    ##
    # Creates a new Resource Wait Manager
    #
    # @param [Fog::Model] resource Fog Model resource
    # @return [Bosh::Google::ResourceWaitManager] Resource Wait Manager
    def initialize(resource)
      @logger = Bosh::Clouds::Config.logger
      @resource = resource
      @description = "#{resource_name} `#{resource_identity}'"
    end

    ##
    # Waits for a resource to be ready
    #
    # @param [Hash] options Wait options
    # @raise [Bosh::Clouds::CloudError] When resource is not found
    # @raise [Bosh::Clouds::CloudError] When resource status is error
    def wait_for(options = {})
      initialize_retry_options(options)

      Bosh::Common.retryable(tries: max_tries, sleep: sleep_callback, ensure: ensure_callback) do
        task_checkpoint

        begin
          cloud_error("#{description} not found") if resource.reload.nil?
        rescue Fog::Errors::Error => e
          cloud_error("#{description} returned an error: #{e.message}")
        end

        resource.ready?
      end
    end

    private

    ##
    # Initializes the wait_for options
    #
    # @param [Hash] options wait_for options
    # @option options [Integer] max_tries Maximum number of retries
    # @option options [Integer] max_sleep_exponent Maximum sleep exponent before retrying a call
    # @return [void]
    def initialize_retry_options(options = {})
      @max_tries = options.fetch(:max_tries, DEFAULT_MAX_TRIES).to_i
      @max_sleep_exponent = options.fetch(:max_sleep_exponent, DEFAULT_MAX_SLEEP_EXPONENT).to_i
      @started_at = Time.now
    end

    ##
    # Callback method called when we must wait before retrying again
    #
    # @return [void]
    def sleep_callback
      lambda do |num_tries, error|
        sleep_time = Kernel.rand(2..2**[num_tries, max_sleep_exponent].min)
        logger.debug("#{error.class}: `#{error.message}'") if error
        logger.debug("Waiting for #{description} to be ready, " \
                     "retrying in #{sleep_time} seconds (#{num_tries}/#{max_tries})")
        sleep_time
      end
    end

    ##
    # Callback method called when the retryable block finishes
    #
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] When resource wait timeouts
    def ensure_callback
      lambda do |retries|
        cloud_error("Timed out waiting for #{description} to be ready, took #{time_passed}s") if retries == max_tries

        logger.debug("#{description} is now ready, took #{time_passed}s")
      end
    end

    ##
    # Returns the Resource name
    #
    # @return [String] Resource name
    def resource_name
      resource.class.name.split('::').last.to_s.downcase
    end

    ##
    # Returns the Resource identity
    #
    # @return [String] Resource identity
    def resource_identity
      resource.identity.to_s
    end

    ##
    # Returns the time passed between a start time and now
    #
    # @return [Integer] Time passed in seconds
    def time_passed
      Time.now - started_at
    end
  end
end
