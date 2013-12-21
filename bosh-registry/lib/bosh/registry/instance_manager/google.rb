# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Registry
  ##
  # BOSH Registry Instance Manager
  #
  class InstanceManager
    ##
    # BOSH Registry Google Compute Engine Instance Manager
    #
    class Google < InstanceManager
      attr_reader   :options
      attr_accessor :logger

      ##
      # Creates a new BOSH Registry Google Compute Engine Instance Manager
      #
      # @param [Hash] options Google Compute Engine options (options are defined in the {file:README.md})
      # @return [Bosh::Registry::InstanceManager::Google] BOSH Registry Google Compute Engine Instance Manager
      def initialize(options)
        @logger = Bosh::Registry.logger

        @options = options.dup
        validate_options
      end

      ##
      # Get the list of IPs belonging to a Google Compute Engine instance
      #
      # @param [String] instance_identity Google Compute Engine instance identity
      # @return [Array<String>] List of instance IPs
      # @raise [Bosh::Registry::InstanceNotFound] if Google Compute Engine instance is not found
      def instance_ips(instance_identity)
        instance = compute_api.servers.get(instance_identity)
        raise InstanceNotFound, "Instance `#{instance_identity}' not found" unless instance

        instance.addresses.compact
      end

      private

      ##
      # Checks if options passed to BOSH Google Compute Engine Instance Manager are valid and can actually be used to
      # create all required data structures
      #
      # @return [void]
      # @raise [Bosh::Registry::ConfigError] if options are not valid
      def validate_options
        required_keys = { 'google' => %w(project client_email pkcs12_key) }

        missing_keys = []

        required_keys.each_pair do |key, values|
          values.each do |value|
            missing_keys << "#{key}:#{value}" unless options.key?(key) && options[key].key?(value)
          end
        end

        raise ConfigError, "Missing configuration parameters: #{missing_keys.join(', ')}" unless missing_keys.empty?
      end

      ##
      # Returns the Fog Google Compute Engine client
      #
      # @return [Fog::Compute::Google] Fog Google Compute Engine client
      # @raise [Bosh::Clouds::CloudError] if unable to connect to the Google Compute Engine API
      def compute_api
        @compute_api ||= Fog::Compute.new(google_connection_params)
      rescue Fog::Errors::Error => e
        logger.error(e)
        raise ConnectionError, 'Unable to connect to the Google Compute Engine API'
      end

      ##
      # Returns the Google Compute Engine connection params
      #
      # @return [Hash] Google Compute Engine connection params
      def google_connection_params
        {
          provider:            'Google',
          google_project:      google_properties.fetch('project'),
          google_client_email: google_properties.fetch('client_email'),
          google_key_string:   Base64.decode64(google_properties.fetch('pkcs12_key'))
        }
      end

      ##
      # Returns the Google Compute Engine properties
      #
      # @return [Hash] Google Compute Engine properties
      def google_properties
        @google_properties ||= options.fetch('google')
      end
    end
  end
end
