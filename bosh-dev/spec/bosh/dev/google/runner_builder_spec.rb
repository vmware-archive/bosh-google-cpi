# -*- encoding: utf-8 -*-
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

require 'spec_helper'
require 'bosh/dev/bat_helper'
require 'bosh/dev/google/runner_builder'

module Bosh::Dev::Google
  describe RunnerBuilder do
    let(:artifacts) { instance_double(Bosh::Dev::Bat::Artifacts, stemcell_path: 'stemcell-path') }
    let(:director_address) { instance_double(Bosh::Dev::Bat::DirectorAddress) }
    let(:bosh_cli_session) { instance_double(Bosh::Dev::BoshCliSession) }
    let(:director_uuid) { instance_double(Bosh::Dev::Bat::DirectorUuid) }
    let(:stemcell_archive) { instance_double(Bosh::Stemcell::Archive) }
    let(:microbosh_deployment_manifest) { instance_double(Bosh::Dev::Google::MicroBoshDeploymentManifest) }
    let(:bat_deployment_manifest) { instance_double(Bosh::Dev::Google::BatDeploymentManifest) }
    let(:microbosh_deployment_cleaner) { instance_double(Bosh::Dev::Google::MicroBoshDeploymentCleaner) }
    let(:runner) { instance_double(Bosh::Dev::Bat::Runner) }

    describe '#build' do
      it 'returns google runner with injected env and proper director address' do
        expect(Bosh::Dev::Bat::DirectorAddress).to receive(:from_env)
                                                   .with(ENV, 'BOSH_GOOGLE_MICROBOSH_IP')
                                                   .and_return(director_address)

        expect(Bosh::Dev::BoshCliSession).to receive(:new)
                                             .with(no_args)
                                             .and_return(bosh_cli_session)

        expect(Bosh::Dev::Bat::DirectorUuid).to receive(:new)
                                                .with(bosh_cli_session)
                                                .and_return(director_uuid)

        expect(Bosh::Stemcell::Archive).to receive(:new)
                                           .with('stemcell-path')
                                           .and_return(stemcell_archive)

        expect(Bosh::Dev::Google::MicroBoshDeploymentManifest).to receive(:new)
                                                                  .with(ENV)
                                                                  .and_return(microbosh_deployment_manifest)

        expect(Bosh::Dev::Google::BatDeploymentManifest).to receive(:new)
                                                            .with(ENV, director_uuid, stemcell_archive)
                                                            .and_return(bat_deployment_manifest)

        expect(Bosh::Dev::Google::MicroBoshDeploymentCleaner).to receive(:new)
                                                                 .with(microbosh_deployment_manifest)
                                                                 .and_return(microbosh_deployment_cleaner)

        expect(Bosh::Dev::Bat::Runner).to receive(:new)
          .with(
            ENV,
            artifacts,
            director_address,
            bosh_cli_session,
            stemcell_archive,
            microbosh_deployment_manifest,
            bat_deployment_manifest,
            microbosh_deployment_cleaner,
            be_an_instance_of(Logger)
          ).and_return(runner)

        expect(subject.build(artifacts, 'net-type')).to eq(runner)
      end
    end
  end
end
