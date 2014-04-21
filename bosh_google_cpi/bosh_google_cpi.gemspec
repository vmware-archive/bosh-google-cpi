# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require File.expand_path('../lib/cloud/google/version', __FILE__)

version = Bosh::Google::VERSION

Gem::Specification.new do |s|
  s.name         = 'bosh_google_cpi'
  s.version      = version
  s.platform     = Gem::Platform::RUBY
  s.summary      = 'BOSH Google Compute Engine CPI'
  s.description  = "BOSH Google Compute Engine CPI\n#{`git rev-parse HEAD`[0, 6]}"
  s.author       = 'Pivotal'
  s.homepage     = 'https://github.com/cloudfoundry/bosh'
  s.license      = 'Apache 2.0'
  s.email        = 'support@cloudfoundry.com'
  s.required_ruby_version = Gem::Requirement.new('>= 1.9.3')

  s.files        = `git ls-files -- bin/* lib/*`.split("\n") + %w(README.md)
  s.require_path = 'lib'
  s.bindir       = 'bin'
  s.executables  = %w(bosh_google_console)

  s.add_dependency 'fog', '~>1.22.0'
  s.add_dependency 'bosh_common', "~>#{version}"
  s.add_dependency 'bosh_cpi', "~>#{version}"
  s.add_dependency 'bosh-registry', "~>#{version}"
  s.add_dependency 'google-api-client', '~>0.6.4'
  s.add_dependency 'httpclient', '=2.2.4'
  s.add_dependency 'yajl-ruby', '>=0.8.2'
end
