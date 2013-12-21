# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

module Bosh::Google
  ##
  # Manages Google Compute Engine Disk Snapshots
  #
  class DiskSnapshotManager
    include Helpers

    attr_reader :logger
    attr_reader :compute_api

    ##
    # Creates a new Google Compute Engine Disk Snapshot Manager
    #
    # @param [Fog::Compute::Google] compute_api Fog Google Compute Engine client
    # @return [Bosh::Google::DiskSnapshotManager] Google Compute Engine Disk Snapshot Manager
    def initialize(compute_api)
      @logger = Bosh::Clouds::Config.logger
      @compute_api = compute_api
    end

    ##
    # Returns an existing Google Compute Engine disk snapshot
    #
    # @param [String] identity Google Compute Engine disk snapshot identity
    # @return [Fog::Compute::Google::Snapshot] Google Compute Engine disk snapshot
    # @raise [Bosh::Clouds::CloudError] if Google Compute Engine disk snapshot is not found
    def get(identity)
      disk_snapshot = compute_api.snapshots.get(identity)
      cloud_error("Disk snapshot `#{identity}' not found") unless disk_snapshot

      disk_snapshot
    end

    ##
    # Creates a snapshot of an existing Google Compute Engine disk
    #
    # @param [Fog::Compute::Google::Disk] disk Google Compute Engine disk
    # @param [Hash] metadata Metadata key/value pairs to add to the disk snapshot
    # @return [Fog::Compute::Google::Snapshot] Google Compute Engine disk snapshot
    def create(disk, metadata)
      disk_snapshot = disk.create_snapshot("snapshot-#{generate_unique_name}", description(metadata))

      logger.debug("Creating new disk snapshot `#{disk_snapshot.identity}' from disk `#{disk.identity}'...")
      ResourceWaitManager.wait_for(disk_snapshot)

      disk_snapshot.reload
    end

    ##
    # Deletes an existing Google Compute Engine disk snapshot
    #
    # @param [String] identity Google Compute Engine disk snapshot identity
    # @return [void]
    # @raise [Bosh::Clouds::CloudError] if  Google Compute Engine disk snapshot is not in a ready state
    def delete(identity)
      disk_snapshot = get(identity)

      unless disk_snapshot.ready?
        cloud_error("Cannot delete disk snapshot `#{identity}', status is `#{disk_snapshot.status}'")
      end

      operation = disk_snapshot.destroy
      ResourceWaitManager.wait_for(operation)
    end

    private

    ##
    # Returns the description to be used to create a new Google Compute Engine disk snapshot
    #
    # @param [Hash] metadata Metadata key/value pairs to add to the disk snapshot
    # @return [String] Disk snapshot description
    def description(metadata)
      [:deployment, :job, :index].map { |key| metadata[key] }.join('/')
    end
  end
end
