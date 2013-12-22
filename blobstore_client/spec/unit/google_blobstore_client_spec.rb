# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'fog'
require 'fog/google/models/storage/directories'
require 'fog/google/models/storage/files'

module Bosh::Blobstore
  describe GoogleBlobstoreClient do
    let(:subject) { described_class }

    let(:oid) { 'object-id' }
    let(:contents) { 'File contents' }
    let(:bucket_name) { 'bucket-name' }
    let(:access_key_id) { 'KEY' }
    let(:secret_access_key) { 'SECRET' }
    let(:encryption_key) { nil }
    let(:google_storage_endpoint) { 'https://storage.googleapis.com/' }
    let(:options_read_write) {
      {
        'bucket_name' => bucket_name,
        'access_key_id' => access_key_id,
        'secret_access_key' => secret_access_key,
        'encryption_key' => encryption_key
      }
    }
    let(:client_read_write) { subject.new(options_read_write) }
    let(:options_read_only) {
      {
        'bucket_name' => bucket_name,
        'endpoint' => google_storage_endpoint,
        'encryption_key' => encryption_key
      }
    }
    let(:client_read_only) { subject.new(options_read_only) }
    let(:unique_name) { SecureRandom.uuid }
    let(:temp_file_name) { SecureRandom.uuid }

    let(:fog_storage) { double(Fog::Storage::Google) }
    let(:fog_directories) { double(Fog::Storage::Google::Directories) }
    let(:fog_directory) { double(Fog::Storage::Google::Directory) }
    let(:fog_files) { double(Fog::Storage::Google::Files) }
    let(:fog_file) { double(Fog::Storage::Google::File) }
    let(:simple_blobstore) { double(SimpleBlobstoreClient) }
    let(:cypher) { double(OpenSSL::Cipher::Cipher) }

    describe 'new' do
      it 'should raise a BlobstoreError exception if options does not contain bucket name' do
        expect do
          subject.new({})
        end.to raise_error(BlobstoreError, 'Bucket name is missing')
      end

      context 'Read/Write mode' do
        let(:fog_storage_options) {
          {
            provider: 'google',
            google_storage_access_key_id: access_key_id,
            google_storage_secret_access_key: secret_access_key
          }
        }

        it 'should create a Fog::Storage instance' do
          expect(Fog::Storage).to receive(:new).with(fog_storage_options)

          subject.new(options_read_write)
        end
      end

      context 'Read only mode' do
        let(:simpleblobstore_options) {
          {
            bucket: bucket_name,
            endpoint: google_storage_endpoint
          }
        }

        it 'should create a SimpleBlobstoreClient instance' do
          expect(SimpleBlobstoreClient).to receive(:new).with(simpleblobstore_options)

          subject.new(options_read_only)
        end

        context 'with encryption key' do
          let(:encryption_key) { 'encryption-key' }

          it 'should raise a BlobstoreError exception' do
            expect do
              subject.new(options_read_only)
            end.to raise_error(BlobstoreError, 'encryption key is not supported in read-only mode')
          end
        end
      end
    end

    describe 'create' do
      context 'Read/Write mode' do
        before do
          allow(Fog::Storage).to receive(:new).and_return(fog_storage)
          allow(fog_storage).to receive(:directories).and_return(fog_directories)
          allow(fog_directories).to receive(:get).with(bucket_name).and_return(fog_directory)
          allow(fog_directory).to receive(:files).and_return(fog_files)
          allow(SecureRandom).to receive(:uuid).and_return(temp_file_name, unique_name)
        end

        it 'should create the object' do
          expect(fog_files).to receive(:create)

          expect(client_read_write.create(contents)).to eql(unique_name)
        end

        context 'when object should be encrypted' do
          let(:encryption_key) { 'encryption-key' }

          before do
            allow(OpenSSL::Cipher::Cipher).to receive(:new).and_return(cypher)
          end

          it 'should create the object' do
            expect(cypher).to receive(:encrypt)
            expect(cypher).to receive(:key_len).and_return(encryption_key.length)
            expect(cypher).to receive(:key=)
            expect(cypher).to receive(:update).with(contents)
            expect(cypher).to receive(:final)
            expect(fog_files).to receive(:create)

            expect(client_read_write.create(contents)).to eql(unique_name)
          end
        end

        context 'when Fog returns an error' do
          it 'should raise a BlobstoreError exception' do
            expect(fog_files).to receive(:create).and_raise(Fog::Errors::Error)

            expect do
              client_read_write.create(contents)
            end.to raise_error(Bosh::Blobstore::BlobstoreError,
                               'Failed to create object at Google Cloud Storage: Fog::Errors::Error')
          end
        end
      end

      context 'Read only mode' do
        it 'should raise a BlobstoreError exception' do
          expect do
            client_read_only.create(contents)
          end.to raise_error(BlobstoreError, 'Blobstore client is read only, please set credentials')
        end
      end
    end

    describe 'exists?' do
      context 'Read/Write mode' do
        before do
          allow(Fog::Storage).to receive(:new).and_return(fog_storage)
          allow(fog_storage).to receive(:directories).and_return(fog_directories)
          allow(fog_directories).to receive(:get).with(bucket_name).and_return(fog_directory)
          allow(fog_directory).to receive(:files).and_return(fog_files)
        end

        context 'when object exists' do
          it 'should return true' do
            expect(fog_files).to receive(:head).with(oid).and_return(fog_file)

            expect(client_read_write.exists?(oid)).to be_truthy
          end
        end

        context 'when object does not exists' do
          it 'should return false' do
            expect(fog_files).to receive(:head).with(oid).and_return(nil)

            expect(client_read_write.exists?(oid)).to be_falsey
          end
        end

        context 'when Fog returns an error' do
          it 'should raise a BlobstoreError exception' do
            expect(fog_files).to receive(:head).with(oid).and_raise(Fog::Errors::Error)

            expect do
              client_read_write.exists?(oid)
            end.to raise_error(Bosh::Blobstore::BlobstoreError,
                               "Failed to query object `#{oid}' at Google Cloud Storage: Fog::Errors::Error")
          end
        end
      end

      context 'Read only mode' do
        before do
          allow(SimpleBlobstoreClient).to receive(:new).and_return(simple_blobstore)
        end

        context 'when object exists' do
          it 'should return true' do
            expect(simple_blobstore).to receive(:exists?).with(oid).and_return(true)

            expect(client_read_only.exists?(oid)).to be_truthy
          end
        end

        context 'when object does not exists' do
          it 'should return false' do
            expect(simple_blobstore).to receive(:exists?).with(oid).and_return(false)

            expect(client_read_only.exists?(oid)).to be_falsey
          end
        end
      end
    end

    describe '#get' do
      context 'Read/Write mode' do
        before do
          allow(Fog::Storage).to receive(:new).and_return(fog_storage)
          allow(fog_storage).to receive(:directories).and_return(fog_directories)
          allow(fog_directories).to receive(:get).with(bucket_name).and_return(fog_directory)
          allow(fog_directory).to receive(:files).and_return(fog_files)
        end

        it 'should return the contents of the file' do
          expect(fog_files).to receive(:get).with(oid).and_yield(contents)

          expect(client_read_write.get(oid)).to eql(contents)
        end

        context 'when object is encrypted' do
          let(:encryption_key) { 'encryption-key' }

          before do
            allow(OpenSSL::Cipher::Cipher).to receive(:new).and_return(cypher)
          end

          it 'should return the contents of the file' do
            expect(cypher).to receive(:decrypt)
            expect(cypher).to receive(:key_len).and_return(encryption_key.length)
            expect(cypher).to receive(:key=)
            expect(fog_files).to receive(:get).with(oid).and_yield(contents)
            expect(cypher).to receive(:update).with(contents).and_return(contents)
            expect(cypher).to receive(:final)

            expect(client_read_write.get(oid)).to eql(contents)
          end
        end

        context 'when object does not exists' do
          it 'should raise a NotFound exception' do
            expect(fog_files).to receive(:get).with(oid).and_return(nil)

            expect do
              client_read_write.get(oid)
            end.to raise_error(Bosh::Blobstore::NotFound, "Object `#{oid}' not found at Google Cloud Storage")
          end
        end

        context 'when Fog returns an error' do
          it 'should raise a BlobstoreError exception' do
            expect(fog_files).to receive(:get).with(oid).and_raise(Fog::Errors::Error)

            expect do
              client_read_write.get(oid)
            end.to raise_error(Bosh::Blobstore::BlobstoreError,
                               "Failed to get object `#{oid}' at Google Cloud Storage: Fog::Errors::Error")
          end
        end

        context 'when bucket does not exists' do
          it 'should raise a NotFound exception' do
            allow(fog_directories).to receive(:get).with(bucket_name).and_return(nil)

            expect do
              client_read_write.get(oid)
            end.to raise_error(Bosh::Blobstore::NotFound,
                               "Bucket `#{bucket_name}' not found at Google Cloud Storage")
          end
        end

        context 'when Fog returns an error querying for the bucket' do
          it 'should raise a BlobstoreError exception' do
            allow(fog_directories).to receive(:get).with(bucket_name).and_raise(Fog::Errors::Error)

            expect do
              client_read_write.get(oid)
            end.to raise_error(Bosh::Blobstore::BlobstoreError,
                               "Failed to query bucket `#{bucket_name}' at Google Cloud Storage: Fog::Errors::Error")
          end
        end
      end

      context 'Read only mode' do
        before do
          allow(SimpleBlobstoreClient).to receive(:new).and_return(simple_blobstore)
        end

        it 'should delegate the call to the SimpleBlobstoreClient' do
          expect(simple_blobstore).to receive(:get_file)

          client_read_only.get(oid)
        end
      end
    end

    describe '#delete' do
      context 'Read/Write mode' do
        before do
          allow(Fog::Storage).to receive(:new).and_return(fog_storage)
          allow(fog_storage).to receive(:directories).and_return(fog_directories)
          allow(fog_directories).to receive(:get).with(bucket_name).and_return(fog_directory)
          allow(fog_directory).to receive(:files).and_return(fog_files)
        end

        it 'should delete an object' do
          expect(fog_files).to receive(:head).with(oid).and_return(fog_file)
          expect(fog_file).to receive(:destroy)

          client_read_write.delete(oid)
        end

        context 'when object does not exists' do
          it 'should raise a NotFound exception' do
            expect(fog_files).to receive(:head).with(oid).and_return(nil)

            expect do
              client_read_write.delete(oid)
            end.to raise_error(Bosh::Blobstore::NotFound, "Object `#{oid}' not found at Google Cloud Storage")
          end
        end

        context 'when Fog returns an error' do
          it 'should raise a BlobstoreError exception' do
            expect(fog_files).to receive(:head).with(oid).and_raise(Fog::Errors::Error)

            expect do
              client_read_write.delete(oid)
            end.to raise_error(Bosh::Blobstore::BlobstoreError,
                               "Failed to delete object `#{oid}' at Google Cloud Storage: Fog::Errors::Error")
          end
        end
      end

      context 'Read only mode' do
        it 'should raise a BlobstoreError exception' do
          expect do
            client_read_only.delete(oid)
          end.to raise_error(BlobstoreError, 'Blobstore client is read only, please set credentials')
        end
      end
    end
  end
end
