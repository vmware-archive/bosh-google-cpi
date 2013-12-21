# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.
require 'spec_helper'

describe 'Google Stemcell' do
  context 'installed by system_parameters' do
    describe file('/var/vcap/bosh/etc/infrastructure') do
      it { should contain('google') }
    end
  end

  context 'installed by image_install_grub' do
    describe file('/boot/grub/grub.conf') do
      it { should be_file }
      it { should contain 'serial --unit=0 --speed=38400' }
      it { should contain 'terminal --timeout=5 serial console' }
      it { should contain ' console=ttyS0,38400n8' }
    end
  end

  context 'installed by system_google_packages' do
    describe file('/etc/init.d/google') do
      it { should be_file }
      it { should be_executable }
    end

    describe file('/etc/init.d/google-accounts-manager') do
      it { should be_file }
      it { should be_executable }
    end

    describe file('/etc/init.d/google-address-manager') do
      it { should be_file }
      it { should be_executable }
    end

    describe file('/etc/init.d/google-startup-scripts') do
      it { should be_file }
      it { should be_executable }
    end
  end
end
