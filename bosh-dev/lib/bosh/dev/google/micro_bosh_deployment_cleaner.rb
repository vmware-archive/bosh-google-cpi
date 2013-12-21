# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'logger'
require 'sequel'
require 'sequel/adapters/sqlite'
require 'cloud/google'
require 'common/retryable'
require 'bosh/dev/google'

module Bosh::Dev::Google
  class MicroBoshDeploymentCleaner
    def initialize(manifest)
      @manifest = manifest
      @logger = Logger.new($stderr)
      configure_cpi
      @cloud = Bosh::Google::Cloud.new(@manifest.cpi_options)
    end

    def clean
      servers_collection = @cloud.compute_api.servers

      Bosh::Retryable.new(tries: 20, sleep: 20).retryer do
        servers = find_any_matching_servers(servers_collection)

        matching_server_names = servers.map(&:name).join(', ')
        @logger.info("Destroying servers #{matching_server_names}")

        servers.each { |s| clean_server(s) }

        servers.empty?
      end
    end

    def clean_server(server)
      disks = server.disks

      operation = server.destroy
      Bosh::Retryable.new({ tries: 10, sleep: 5 }).retryer do
        operation.reload
        operation.ready?
      end

      disks.each do |disk|
        disk_name = disk['source'].split('/').last
        @cloud.compute_api.disks.get(disk_name, @manifest.zone).destroy
      end
    end

    private

    def configure_cpi
      Bosh::Clouds::Config.configure(OpenStruct.new(
        logger: @logger,
        uuid: nil,
        task_checkpoint: nil,
        db: Sequel.sqlite
      ))
    end

    def find_any_matching_servers(servers_collection)
      # Assumption here is that when director deploys instances
      # it properly tags them with director's name.
      servers_collection.select do |server|
        metadata = server.metadata['items'] || []
        tag = metadata.find { |item| item['key'] == 'director' || item['key'] == 'Name'} || {}
        tag['value'] == @manifest.director_name ? true : false
      end
    end
  end
end
