# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'tempfile'
require 'net/http'

module Bosh::Blobstore
  describe GoogleBlobstoreClient, google_credentials: true do
    def access_key_id
      key = ENV['GOOGLE_ACCESS_KEY_ID']
      raise 'need to set GOOGLE_ACCESS_KEY_ID environment variable' unless key
      key
    end

    def secret_access_key
      key = ENV['GOGGLE_SECRET_ACCESS_KEY']
      raise 'need to set GOOGLE_SECRET_ACCESS_KEY environment variable' unless key
      key
    end

    attr_reader :bucket_name

    let(:google) do
      Client.create('google', google_options)
    end
    let(:contents) { 'File contents' }
    let(:encryption_key) { 'nil' }

    before(:all) do
      google = Fog::Storage.new(
        provider: 'google',
        google_storage_access_key_id: access_key_id,
        google_storage_secret_access_key: secret_access_key
      )

      @bucket_name = sprintf('bosh-blobstore-bucket-%08x', rand(2**32))
      @bucket = google.directories.create(key: @bucket_name, acl: 'public-read')
      @object = @bucket.files.create(key: 'public', body: 'File contents', acl: 'public-read')
    end

    after(:all) do
      @object.destroy
      @bucket.destroy
    end

    context 'Read/Write mode' do
      let(:google_options) do
        {
          bucket_name: bucket_name,
          access_key_id: access_key_id,
          secret_access_key: secret_access_key,
          encryption_key: encryption_key
        }
      end

      after(:each) do
        google.delete(@oid) if @oid
      end

      describe 'unencrypted' do
        describe '#create' do
          it 'should store a file' do
            file_path = File.join(Dir.tmpdir, SecureRandom.uuid)
            File.open(file_path, 'w') { |f| f.write(contents) }

            @oid = google.create(File.open(file_path, 'r'))

            expect(@oid).not_to be_nil
            expect(google.get(@oid)).to eql(contents)
          end

          it 'should store a string' do
            @oid = google.create(contents)

            expect(@oid).to_not be_nil
            expect(google.get(@oid)).to eql(contents)
          end
        end

        describe '#exists?' do
          it 'should return true if the object exist' do
            @oid = google.create(contents)

            expect(google.exists?(@oid)).to be_truthy
          end

          it 'should return false if the object does not exist' do
            expect(google.exists?('unexisting')).to be_falsey
          end
        end

        describe '#get' do
          it 'should return the contents in a file' do
            @oid = google.create(contents)

            file = Tempfile.new('google')
            google.get(@oid, file)
            file.rewind
            expect(file.read).to eql(contents)
          end

          it 'should return the contents in a string' do
            @oid = google.create(contents)

            expect(google.get(@oid)).to eql(contents)
          end

          it 'should raise a Blobstore exception when object does not exist' do
            expect do
              google.get('unexisting')
            end.to raise_error(BlobstoreError, "Object `unexisting' not found at Google Cloud Storage")
          end
        end

        describe '#delete' do
          it 'should delete an object' do
            @oid = google.create(contents)

            expect do
              google.delete(@oid)
            end.to_not raise_error

            @oid = nil
          end

          it 'should raise a Blobstore exception when object does not exist' do
            expect do
              google.delete('unexisting')
            end.to raise_error(BlobstoreError, "Object `unexisting' not found at Google Cloud Storage")
          end
        end
      end

      describe 'encrypted' do
        let(:encryption_key) { 'encryption-key' }

        describe '#create' do
          it 'should store a file encrypted' do
            file_path = File.join(Dir.tmpdir, SecureRandom.uuid)
            File.open(file_path, 'w') { |f| f.write(contents) }

            @oid = google.create(File.open(file_path, 'r'))

            expect(@oid).not_to be_nil
            expect(google.get(@oid)).to eql(contents)
          end

          it 'should store a string encrypted' do
            @oid = google.create(contents)

            expect(@oid).to_not be_nil
            expect(google.get(@oid)).to eql(contents)
          end
        end
      end
    end

    context 'Read only mode' do
      let(:google_options) do
        { bucket_name: bucket_name }
      end

      describe '#create' do
        it 'should raise an error' do
          expect do
            google.create(contents)
          end.to raise_error BlobstoreError, 'Blobstore client is read only, please set credentials'
        end
      end

      describe '#get' do
        it 'should return the contents in a file' do
          file = Tempfile.new('google')
          google.get('public', file)
          file.rewind
          expect(file.read).to eql(contents)
        end

        it 'should return the contents in a string' do
          expect(google.get('public')).to eql(contents)
        end

        it 'should raise a Blobstore exception when object does not exist' do
          expect do
            google.get('unexisting')
          end.to raise_error(BlobstoreError, 'Could not fetch object, 404/')
        end
      end

      describe 'exists?' do
        it 'should return true if exists' do
          expect(google.exists?('public')).to be_truthy
        end

        it 'should return false if does not exists' do
          expect(google.exists?('unexisting')).to be_falsey
        end
      end

      describe '#delete' do
        it 'should raise an error' do
          expect do
            google.delete('public')
          end.to raise_error BlobstoreError, 'Blobstore client is read only, please set credentials'
        end
      end
    end
  end
end
