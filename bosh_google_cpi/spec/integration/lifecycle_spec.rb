# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.
require 'spec_helper'
require 'tempfile'
require 'cloud'
require 'logger'
require 'fog'

module Bosh::Google
  describe Cloud, google_credentials: true do
    before(:all) do
      @project           = ENV['BOSH_GOOGLE_PROJECT']           || raise('Missing BOSH_GOOGLE_PROJECT')
      @client_email      = ENV['BOSH_GOOGLE_CLIENT_EMAIL']      || raise('Missing BOSH_GOOGLE_CLIENT_EMAIL')
      @pkcs12_key        = ENV['BOSH_GOOGLE_PKCS12_KEY_FILE']   || raise('Missing BOSH_GOOGLE_PKCS12_KEY_FILE')
      @default_zone      = ENV['BOSH_GOOGLE_DEFAULT_ZONE']      || raise('Missing BOSH_GOOGLE_DEFAULT_ZONE')
      @access_key_id     = ENV['BOSH_GOOGLE_ACCESS_KEY_ID']     || raise('Missing BOSH_GOOGLE_ACCESS_KEY_ID')
      @secret_access_key = ENV['BOSH_GOOGLE_SECRET_ACCESS_KEY'] || raise('Missing BOSH_GOOGLE_SECRET_ACCESS_KEY')
      @image_name        = ENV['BOSH_GOOGLE_IMAGE_NAME']        || raise('Missing BOSH_GOOGLE_IMAGE_NAME')
    end

    subject(:cpi) do
      described_class.new(
        'google' => {
          'project'       => @project,
          'client_email'  => @client_email,
          'pkcs12_key'    => Base64.encode64(File.new(@pkcs12_key, 'rb').read),
          'default_zone'  => @default_zone,
          'access_key_id' => @access_key_id,
          'secret_access_key' => @secret_access_key
        },
        'registry' => {
          'endpoint' => 'fake',
          'user'     => 'fake',
          'password' => 'fake'
        }
      )
    end

    before do
      delegate = double('delegate', task_checkpoint: nil, logger: logger)
      Bosh::Clouds::Config.configure(delegate)
    end

    let(:logger) { Logger.new(STDERR) }

    before do
      allow(Bosh::Registry::Client).to receive(:new).and_return(double(Bosh::Registry::Client).as_null_object)
    end

    describe 'google' do
      let(:network_spec) do
        {
          'default' => {
            'type' => 'dynamic',
            'cloud_properties' => {
              'tags' => %w(bosh google-cpi-spec)
            }
          }
        }
      end

      context 'without existing disks' do
        it 'should exercise the vm lifecycle' do
          vm_lifecycle(@image_name, network_spec, [])
        end
      end

      context 'with existing disks' do
        before { @existing_disk_id = cpi.create_disk(2048) }
        after { cpi.delete_disk(@existing_disk_id) if @existing_disk_id }

        it 'should exercise the vm lifecycle' do
          vm_lifecycle(@image_name, network_spec, [@existing_disk_id])
        end
      end
    end

    def vm_lifecycle(stemcell_id, network_spec, disk_locality)
      vm_id = create_vm(stemcell_id, network_spec, disk_locality)
      disk_id = create_disk(vm_id)
      disk_snapshot_id = create_disk_snapshot(disk_id)
    rescue Exception => create_error
    ensure
      # create_error is in scope and possibly populated!
      run_all_and_raise_any_errors(create_error, [
        -> { clean_up_disk_snapshot(disk_snapshot_id) },
        -> { clean_up_disk(disk_id) },
        -> { clean_up_vm(vm_id) }
      ])
    end

    def create_vm(stemcell_id, network_spec, disk_locality)
      logger.info("Creating VM with stemcell_id=#{stemcell_id}")
      vm_id = cpi.create_vm(
        'agent-007',
        stemcell_id,
        { 'instance_type' => 'n1-standard-1' },
        network_spec,
        disk_locality,
        'key' => 'value'
      )
      expect(vm_id).to_not be_nil

      logger.info("Checking VM existence vm_id=#{vm_id}")
      cpi.has_vm?(vm_id).should be(true)

      logger.info("Configuring VM network vm_id=#{vm_id}")
      cpi.configure_networks(vm_id, network_spec)

      logger.info("Setting VM metadata vm_id=#{vm_id}")
      cpi.set_vm_metadata(vm_id, deployment: 'deployment', job: 'google_cpi_spec', index: '0')

      vm_id
    end

    def clean_up_vm(vm_id)
      if vm_id
        logger.info("Deleting VM vm_id=#{vm_id}")
        cpi.delete_vm(vm_id)

        logger.info("Checking VM existence vm_id=#{vm_id}")
        cpi.has_vm?(vm_id).should be(false)
      else
        logger.info('No VM to delete')
      end
    end

    def create_disk(vm_id)
      logger.info("Creating disk for VM vm_id=#{vm_id}")
      disk_id = cpi.create_disk(2048, vm_id)
      expect(disk_id).to_not be_nil

      logger.info("Attaching disk vm_id=#{vm_id} disk_id=#{disk_id}")
      cpi.attach_disk(vm_id, disk_id)

      logger.info("Getting disks for VM vm_id=#{vm_id}")
      cpi.get_disks(vm_id).should eq [disk_id]

      logger.info("Detaching disk vm_id=#{vm_id} disk_id=#{disk_id}")
      cpi.detach_disk(vm_id, disk_id)

      disk_id
    end

    def clean_up_disk(disk_id)
      if disk_id
        logger.info("Deleting disk disk_id=#{disk_id}")
        cpi.delete_disk(disk_id)
      else
        logger.info('No disk to delete')
      end
    end

    def create_disk_snapshot(disk_id)
      logger.info("Creating disk snapshot disk_id=#{disk_id}")
      disk_snapshot_id = cpi.snapshot_disk(disk_id,
        deployment: 'deployment',
        job: 'google_cpi_spec',
        index: '0',
        instance_id: 'instance',
        agent_id: 'agent',
        director_name: 'Director',
        director_uuid: '6d06b0cc-2c08-43c5-95be-f1b2dd247e18'
      )
      expect(disk_snapshot_id).to_not be_nil

      logger.info("Created disk snapshot disk_snapshot_id=#{disk_snapshot_id}")
      disk_snapshot_id
    end

    def clean_up_disk_snapshot(disk_snapshot_id)
      if disk_snapshot_id
        logger.info("Deleting disk snapshot disk_snapshot_id=#{disk_snapshot_id}")
        cpi.delete_snapshot(disk_snapshot_id)
      else
        logger.info('No disk snapshot to delete')
      end
    end

    def run_all_and_raise_any_errors(existing_errors, funcs)
      exceptions = Array(existing_errors)
      funcs.each do |f|
        begin
          f.call
        rescue Exception => e
          exceptions << e
        end
      end
      # Prints all exceptions but raises original exception
      exceptions.each { |e| logger.info("Failed with: #{e.inspect}\n#{e.backtrace.join("\n")}\n") }
      raise exceptions.first if exceptions.any?
    end
  end
end
