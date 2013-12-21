# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.
require 'timeout'
require 'httpclient'

module Bosh::Google
  ##
  # Manages BOSH Registry calls
  #
  class RegistryManager
    include Helpers

    MAX_TRIES          = 3 # Maximum number of retries
    MAX_SLEEP_EXPONENT = 3 # Maximum sleep exponent before retrying a call

    attr_reader :logger
    attr_reader :registry

    ##
    # Creates a new BOSH Registry Manager
    #
    # @param [Hash] options Bosh Registry options
    # @return [Bosh::Google::RegistryManager] BOSH Registry Manager
    def initialize(options)
      @logger = Bosh::Clouds::Config.logger
      @registry = initialize_registry_client(options)
    end

    ##
    # Reads BOSH Registry settings for a vm
    #
    # @param [String] vm_id VM id
    # @return [Hash] Settings for vm
    def read(vm_id)
      logger.debug("Reading BOSH Registry settings for vm `#{vm_id}'...")
      perform(:read, vm_id)
    end

    ##
    # Updates BOSH Registry settings for a vm
    #
    # @param [String] vm_id VM id
    # @param [Hash] settings Settings for vm
    # @return [void]
    def update(vm_id, settings)
      logger.debug("Updating BOSH Registry settings for vm `#{vm_id}'...")
      perform(:update, vm_id, settings)
    end

    ##
    # Deletes BOSH Registry settings for a vm
    #
    # @param [String] vm_id VM id
    # @return [void]
    def delete(vm_id)
      logger.debug("Deleting BOSH Registry settings for vm `#{vm_id}'...")
      perform(:delete, vm_id)
    end

    private

    ##
    # Initialize the Bosh Registry client
    #
    # @return [Bosh::Registry::Client] Bosh Registry client
    def initialize_registry_client(options)
      endpoint   = options.fetch('endpoint')
      user       = options.fetch('user')
      password   = options.fetch('password')

      @registry = Bosh::Registry::Client.new(endpoint, user, password)
    end

    ##
    # Performs an action against BOSH Registry
    #
    # @param [Symbol] action Action to be performed (:read, :update, :delete)
    # @param [String] vm_id VM id
    # @param [Hash] settings Settings for vm
    # @return [Hash] if action is :read
    # @return [void] if action is not :read
    def perform(action, vm_id, settings = {})
      exceptions = [EOFError, Errno::ECONNREFUSED, Errno::ECONNRESET, Errno::EINVAL, SocketError, Timeout::Error,
                    HTTPClient::ConnectTimeoutError, HTTPClient::ReceiveTimeoutError, HTTPClient::SendTimeoutError,
                    HTTPClient::TimeoutError]
      Bosh::Common.retryable(tries: MAX_TRIES, sleep: sleep_callback, ensure: ensure_callback, on: exceptions) do
        task_checkpoint

        method = "#{action}_settings".to_sym
        args = action == :update ? [vm_id, settings] : [vm_id]
        registry.send(method, *args)
      end
    end

    ##
    # Callback method called when we must wait before retrying again
    #
    # @return [void]
    def sleep_callback
      lambda do |num_tries, error|
        sleep_time = 2**[num_tries, MAX_SLEEP_EXPONENT].min # Exp backoff: 2, 4, 8, 16, 32 ...
        logger.debug("BOSH Registry #{error.class}: `#{error.message}'") if error
        logger.debug("Retrying BOSH Registry call in #{sleep_time} seconds (#{num_tries}/#{MAX_TRIES})")
        sleep_time
      end
    end

    ##
    # Callback method called when the retryable block finishes
    #
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] On timeouts
    def ensure_callback
      lambda do |retries|
        cloud_error('Timed out waiting for BOSH Registry') if retries == MAX_TRIES
      end
    end
  end
end
