# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.
require 'bosh/deployer/registry'
require 'bosh/deployer/remote_tunnel'
require 'bosh/deployer/ssh_server'

module Bosh::Deployer
  class InstanceManager
    class Google
      def initialize(instance_manager, config, logger)
        @instance_manager = instance_manager
        @logger = logger
        @config = config
        properties = config.cloud_options['properties']

        @registry = Registry.new(
            properties['registry']['endpoint'],
            'google',
            properties['google'],
            instance_manager,
            logger
        )

        ssh_key, ssh_port, ssh_user, ssh_wait = ssh_properties(properties)
        ssh_server = SshServer.new(ssh_user, ssh_key, ssh_port, logger)
        @remote_tunnel = RemoteTunnel.new(ssh_server, ssh_wait, logger)
      end

      def remote_tunnel
        @remote_tunnel.create(instance_manager.client_services_ip, registry.port)
      end

      def disk_model
        nil
      end

      def update_spec(spec)
        properties = spec.properties

        properties['google'] =
            config.spec_properties['google'] ||
            config.cloud_options['properties']['google'].dup

        properties['google']['registry'] = config.cloud_options['properties']['registry']

        spec.delete('networks')
      end

      def check_dependencies
        # nothing to check, move on...
      end

      def start
        registry.start
      end

      def stop
        registry.stop
        instance_manager.save_state
      end

      def client_services_ip
        discover_client_services_ip
      end

      def agent_services_ip
        discover_agent_services_ip
      end

      def internal_services_ip
        config.internal_services_ip
      end

      def persistent_disk_changed?
        requested = (config.resources['persistent_disk'] / 1024.0).ceil * 1024
        requested != disk_size(instance_manager.state.disk_cid)
      end

      private

      attr_reader :registry, :instance_manager, :logger, :config

      def disk_size(cid)
        instance_manager.cloud.compute_api.disks.get(cid).size_gb.to_i * 1024
      end

      def ssh_properties(properties)
        ssh_user = properties['google']['ssh_user']
        ssh_port = properties['google']['ssh_port'] || 22
        ssh_wait = properties['google']['ssh_wait'] || 60

        key = properties['google']['private_key']
        err 'Missing properties.google.private_key' unless key

        ssh_key = File.expand_path(key)
        unless File.exists?(ssh_key)
          err "properties.google.private_key '#{key}' does not exist"
        end

        [ssh_key, ssh_port, ssh_user, ssh_wait]
      end

      def discover_client_services_ip
        if instance_manager.state.vm_cid
          server = instance_manager.cloud.compute_api.servers.get(instance_manager.state.vm_cid)
          ip = server.public_ip_address || server.private_ip_address

          logger.info("discovered bosh ip=#{ip}")
          ip
        else
          default_ip = config.client_services_ip
          logger.info("ip address not discovered - using default of #{default_ip}")
          default_ip
        end
      end

      def discover_agent_services_ip
        if instance_manager.state.vm_cid
          server = instance_manager.cloud.compute_api.servers.get(instance_manager.state.vm_cid)
          ip = server.private_ip_address

          logger.info("discovered bosh ip=#{ip}")
          ip
        else
          default_ip = config.agent_services_ip
          logger.info("ip address not discovered - using default of #{default_ip}")
          default_ip
        end
      end
    end
  end
end
