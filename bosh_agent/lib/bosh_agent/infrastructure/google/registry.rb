# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Agent
  ##
  # BOSH Agent registry for Infrastructure Google Compute Engine
  #
  class Infrastructure::Google::Registry
    class << self

      HTTP_API_TIMEOUT     = 300
      HTTP_CONNECT_TIMEOUT = 30
      USER_DATA_URI = 'http://169.254.169.254/computeMetadata/v1/instance/attributes/user_data'

      ##
      # Returns the logger
      #
      # @return [Logger] BOSH Agent logger
      def logger
        Bosh::Agent::Config.logger
      end

      ##
      # Gets the settings for this agent from the BOSH Registry
      #
      # @return [Hash] Agent Settings
      # @raise [Bosh::Agent::LoadSettingsError] if can not get settings
      def get_settings
        registry_data = get_json_from_uri("#{get_registry_endpoint}/instances/#{get_vm_id}/settings")
        unless registry_data.has_key?('settings')
          raise LoadSettingsError, "Invalid response received from BOSH registry: #{registry_data}"
        end

        settings = parse_yajl_data(registry_data['settings'])

        logger.info("Agent settings: #{settings.inspect}")
        settings
      end

      private

      ##
      # Gets the user data from the Google Compute Engine metadata endpoint
      #
      # @return [Hash] User data
      # @raise [Bosh::Agent::LoadSettingsError] if can not get user data
      def get_user_data
        get_json_from_uri(USER_DATA_URI)
      rescue LoadSettingsError => e
        raise LoadSettingsError, "Failed to get user data from Google Compute Engine metadata endpoint: #{e.inspect}"
      end

      ##
      # Gets the BOSH Registry endpoint
      #
      # @return [String] BOSH Registry endpoint
      # @raise [Bosh::Agent::LoadSettingsError] if can not get the registry endpoint
      def get_registry_endpoint
        user_data = get_user_data
        unless user_data.has_key?('registry') && user_data['registry'].has_key?('endpoint')
          raise LoadSettingsError, 'Cannot get BOSH registry endpoint from user data'
        end

        lookup_registry_endpoint(user_data)
      end

      ##
      # If the BOSH Registry endpoint is specified with a DNS name, i.e. 0.registry.default.google.microbosh,
      # then the agent needs to lookup the name and insert the IP address, as the agent doesn't update
      # resolv.conf until after the bootstrap is run
      #
      # @param [Hash] user_data User data
      # @return [String] BOSH Registry endpoint
      # @raise [Bosh::Agent::LoadSettingsError] if can not look up the registry hostname
      def lookup_registry_endpoint(user_data)
        registry_endpoint = user_data['registry']['endpoint']

        # If user data doesn't contain dns info, there is noting we can do, so just return the endpoint
        return registry_endpoint if user_data['dns'].nil? || user_data['dns']['nameserver'].nil?

        # If the endpoint is an IP address, just return the endpoint
        registry_hostname = extract_registry_hostname(registry_endpoint)
        return registry_endpoint if hostname_is_ip_address?(registry_hostname)

        nameservers = user_data['dns']['nameserver']
        registry_ip = lookup_registry_ip_address(registry_hostname, nameservers)

        inject_registry_ip_address(registry_ip, registry_endpoint)
      rescue Resolv::ResolvError => e
        raise LoadSettingsError, "Cannot lookup #{registry_hostname} using #{nameservers.join(", ")}: #{e.inspect}"
      end

      ##
      # Extracts the hostname from the BOSH Registry endpoint
      #
      # @param [String] endpoint BOSH Registry endpoint
      # @return [String] BOSH Registry hostname
      # @raise [Bosh::Agent::LoadSettingsError] if can not extract the registry endpoint
      def extract_registry_hostname(endpoint)
        match = endpoint.match(%r{https*://([^:]+):})
        unless match && match.size == 2
          raise LoadSettingsError, "Cannot extract Bosh registry hostname from #{endpoint}"
        end

        match[1]
      end

      ##
      # Checks if a hostname is an IP address
      #
      # @param [String] hostname Hostname
      # @return [Boolean] True if hostname is an IP address, false otherwise
      def hostname_is_ip_address?(hostname)
        begin
          IPAddr.new(hostname)
        rescue
          return false
        end
        true
      end

      ##
      # Lookups for the BOSH Registry IP address
      #
      # @param [String] hostname BOSH Registry hostname
      # @param [Array] nameservers Array containing nameserver address
      # @return [Resolv::IPv4] BOSH Registry IP address
      def lookup_registry_ip_address(hostname, nameservers)
        resolver = Resolv::DNS.new(nameserver: nameservers)
        resolver.getaddress(hostname)
      end

      ##
      # Injects an IP address into the BOSH Registry endpoint
      #
      # @param [Resolv::IPv4] ip BOSH Registry IP address
      # @param [String] endpoint BOSH Registry endpoint
      # @return [String] BOSH Registry endpoint
      def inject_registry_ip_address(ip, endpoint)
        endpoint.sub(%r{//[^:]+:}, "//#{ip}:")
      end

      ##
      # Gets the VM id
      #
      # @return [String] VM id
      # @raise [Bosh::Agent::LoadSettingsError] if can not get the vm id
      def get_vm_id
        user_data = get_user_data
        unless user_data.has_key?('instance') && user_data['instance'].has_key?('name')
          raise LoadSettingsError, 'Cannot get instance name from user data'
        end

        user_data['instance']['name']
      end

      ##
      # Parses a Yajl encoded data
      #
      # @param [String] raw_data Raw data
      # @return [Hash] Json data
      # @raise [Bosh::Agent::LoadSettingsError] if raw date is invalid
      def parse_yajl_data(raw_data)
        begin
          data = Yajl::Parser.parse(raw_data)
        rescue Yajl::ParseError => e
          raise LoadSettingsError, "Cannot parse data: #{e.message}"
        end

        unless data.is_a?(Hash)
          raise LoadSettingsError, "Invalid data: Hash expected, #{data.class} provided"
        end

        data
      end

      ##
      # Sends GET request to an specified URI and parses response
      #
      # @param [String] uri URI to request
      # @return [String] Decoded response body
      # @raise [Bosh::Agent::LoadSettingsError] if can not get data from URI
      def get_json_from_uri(uri)
        client = HTTPClient.new
        client.send_timeout = HTTP_API_TIMEOUT
        client.receive_timeout = HTTP_API_TIMEOUT
        client.connect_timeout = HTTP_CONNECT_TIMEOUT

        response = client.get(uri, {}, { 'Accept' => 'application/json', 'Metadata-Flavor' => 'Google' })
        raise LoadSettingsError, "Endpoint #{uri} returned HTTP #{response.status}" unless response.status == 200

        parse_yajl_data(response.body)
      rescue URI::Error, HTTPClient::TimeoutError, HTTPClient::BadResponseError, SocketError,
          Errno::EINVAL, Errno::ECONNRESET, Errno::ECONNREFUSED, EOFError, SystemCallError => e
        raise LoadSettingsError, "Error requesting endpoint #{uri}: #{e.inspect}"
      end
    end
  end
end
