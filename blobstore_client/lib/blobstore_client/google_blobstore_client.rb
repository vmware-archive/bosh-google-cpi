# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'base64'
require 'fog'
require 'openssl'
require 'digest/sha1'

module Bosh
  ##
  # BOSH Blobstore Client
  #
  module Blobstore
    ##
    # BOSH Google Cloud Storage Blobstore Client
    #
    class GoogleBlobstoreClient < BaseClient
      DEFAULT_CIPHER_NAME     = 'aes-128-cbc'
      GOOGLE_STORAGE_ENDPOINT = 'https://storage.googleapis.com'

      attr_reader :storage

      ##
      # Creates a new BOSH Google Cloud Storage Blobstore Client
      #
      # @param [Hash] options BOSH Google Cloud Storage Blobstore Client options
      # @option options [Symbol] bucket_name Name of the Google Cloud Storage bucket
      # @option options [optional, Symbol] access_key_id Google Cloud Storage Access Key (client
      #   operates in read only mode if not present)
      # @option options [optional, Symbol] secret_access_key Google Cloud Storage Secret Access
      #   Key (client operates in read only mode if not present)
      # @option options [optional, Symbol] encryption_key Encryption key that is applied before the
      #   object is sent to Google Cloud Storage
      # @option options [optional, Symbol] endpoint Google Cloud Storage public endpoint
      # @return [Bosh::Blobstore::GoogleBlobstoreClient] BOSH Google Cloud Storage Blobstore Client
      def initialize(options)
        super(options)

        initialize_storage_client
      end

      ##
      # Creates and stores a file in the blobstore
      #
      # @param [String] id ID of the object (a random ID will be created if not set)
      # @param [File] file File to be stored in the blobstore
      # @return [String] ID of the stored object
      # @raise [Bosh::Blobstore:BlobstoreError] If blobstore client is read only
      # @raise [Bosh::Blobstore:BlobstoreError] If failed to create the object
      def create_file(id, file)
        raise BlobstoreError, 'Blobstore client is read only, please set credentials' if read_only?

        id ||= generate_object_id

        file = encrypt_file(file) unless encryption_key.nil?
        bucket.files.create(key: id, body: file)

        id
      rescue Fog::Errors::Error => e
        raise BlobstoreError, "Failed to create object at Google Cloud Storage: #{e.message}"
      end

      ##
      # Checks if an object exists in the blobstore
      #
      # @param [String] id ID of the object
      # @return [Boolean] True if the object exists; False otherwise
      # @raise [Bosh::Blobstore:BlobstoreError] If failed to query the object
      def object_exists?(id)
        return storage.exists?(id) if read_only?

        bucket.files.head(id).nil? ? false : true
      rescue Fog::Errors::Error => e
        raise BlobstoreError, "Failed to query object `#{id}' at Google Cloud Storage: #{e.message}"
      end

      ##
      # Gets an object from the blobstore and writes the contents to a file
      #
      # @param [String] id ID of the object
      # @param [File] file File where to store the contents of the object
      # @return [void]
      # @raise [Bosh::Blobstore:NotFound] If object is not found
      # @raise [Bosh::Blobstore:BlobstoreError] If failed to get the object
      def get_file(id, file)
        return storage.get_file(id, file) if read_only?

        if encryption_key
          cipher = OpenSSL::Cipher::Cipher.new(DEFAULT_CIPHER_NAME)
          cipher.decrypt
          cipher.key = Digest::SHA1.digest(encryption_key)[0..(cipher.key_len - 1)]
        end
        object = bucket.files.get(id) do |contents|
          encryption_key ? file.write(cipher.update(contents)) : file.write(contents)
        end
        raise NotFound, "Object `#{id}' not found at Google Cloud Storage" if object.nil?
        file.write(cipher.final) if encryption_key
      rescue Fog::Errors::Error => e
        raise BlobstoreError, "Failed to get object `#{id}' at Google Cloud Storage: #{e.message}"
      end

      ##
      # Deletes an object at the blobstore
      #
      # @param [String] id ID of the object
      # @return [void]
      # @raise [Bosh::Blobstore:BlobstoreError] If blobstore client is read only
      # @raise [Bosh::Blobstore:NotFound] If object is not found
      # @raise [Bosh::Blobstore:BlobstoreError] If failed to delete the object
      def delete_object(id)
        raise BlobstoreError, 'Blobstore client is read only, please set credentials' if read_only?

        object = bucket.files.head(id)
        raise NotFound, "Object `#{id}' not found at Google Cloud Storage" if object.nil?

        object.destroy
      rescue Fog::Errors::Error => e
        raise BlobstoreError, "Failed to delete object `#{id}' at Google Cloud Storage: #{e.message}"
      end

      private

      ##
      # Returns the Google Cloud Storage bucket
      #
      # @return [Fog::Storage::Google::Directory] Google Cloud Storage bucket
      # @raise [Bosh::Blobstore:NotFound] If bucket is not found
      # @raise [Bosh::Blobstore:BlobstoreError] If failed to query the bucket
      def bucket
        bucket = storage.directories.get(bucket_name)
        raise NotFound, "Bucket `#{bucket_name}' not found at Google Cloud Storage" if bucket.nil?

        bucket
      rescue Fog::Errors::Error, Excon::Errors::Forbidden => e
        raise BlobstoreError, "Failed to query bucket `#{bucket_name}' at Google Cloud Storage: #{e.message}"
      end

      ##
      # Returns the bucket name
      #
      # @return [String] Bucket name
      def bucket_name
        @options.fetch(:bucket_name)
      end

      ##
      # Initializes the proper Storage client
      #
      # @return [void]
      def initialize_storage_client
        validate_options(@options)

        @storage = read_only? ? SimpleBlobstoreClient.new(sbc_params) : Fog::Storage.new(gs_conn_params)
      end

      ##
      # Checks if options passed to the blobstore client are valid and can actually be used to create all required
      # data structures
      #
      # @return [void]
      # @raise [Bosh::Blobstore:BlobstoreError] if options are not valid
      def validate_options(options)
        raise BlobstoreError, 'Bucket name is missing' unless options.key?(:bucket_name)
        raise BlobstoreError, 'encryption key is not supported in read-only mode' if read_only? && encryption_key
      end

      ##
      # Determines if the blobstore client operates in read only mode
      #
      # @return [Boolean] True if client operates in read only mode; False otherwise
      def read_only?
        @options[:access_key_id].nil? || @options[:secret_access_key].nil?
      end

      ##
      # Returns the Google Cloud Storage connection params
      #
      # @return [Hash] Google Cloud Storage connection params
      def gs_conn_params
        {
          provider: 'google',
          google_storage_access_key_id: @options.fetch(:access_key_id),
          google_storage_secret_access_key: @options.fetch(:secret_access_key)
        }
      end

      ##
      # Returns the Simple Blobstore Client params
      #
      # @return [Hash] Simple Blobstore Client params
      def sbc_params
        {
          bucket: bucket_name,
          endpoint: @options[:endpoint] || GOOGLE_STORAGE_ENDPOINT
        }
      end

      ##
      # Returns the encryption key
      #
      # @return [String] Encryption key
      def encryption_key
        @options[:encryption_key]
      end

      ##
      # Encrypts a file
      #
      # @param [File] file File to encrypt
      # @return [File] File encrypted
      def encrypt_file(file)
        cipher = OpenSSL::Cipher::Cipher.new(DEFAULT_CIPHER_NAME)
        cipher.encrypt
        cipher.key = Digest::SHA1.digest(encryption_key)[0..(cipher.key_len - 1)]

        path = temp_path
        File.open(path, 'w') do |temp_file|
          while (block = file.read(32_768))
            temp_file.write(cipher.update(block))
          end
          temp_file.write(cipher.final)
        end

        File.new(path, 'r')
      end
    end
  end
end
