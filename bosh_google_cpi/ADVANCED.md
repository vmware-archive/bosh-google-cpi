# Advanced Installation Instructions

WARNING: This tutorial requires an experimental [Google Compute Engine BOSH CPI](https://github.com/cf-platform-eng/bosh-google-cpi) not supported by [Pivotal](http://www.gopivotal.com/).

These are advanced installation instruction for those users that wants to create a BOSH jumpbox instance. If this is not your case, please follow the [Installation Instructions](INSTALL.md) document instead.

## Prepare a jumpbox instance

### Create the jumbox instance

Start a new instance named `bosh-jumpbox`:

```
gcutil addinstance bosh-jumpbox --machine_type=n1-standard-2 --image=debian-7 --zone=us-central1-a \
    --auto_delete_boot_disk --wait_until_running --service_account_scopes=compute-rw,storage-full
```

Create a new persistent disk, so if the vm dies, we won't lose all of our work:

```
gcutil adddisk bosh-jumpbox-persistent --size_gb 200 --zone=us-central1-a --wait_until_complete
```

Attach the persistent disk to the jumpbox instance:

```
gcutil attachdisk bosh-jumpbox --disk bosh-jumpbox-persistent
```

SSH into the jumpbox instance:

```
gcutil ssh bosh-jumpbox
```

### Setup the jumpbox instance

Format and mount the previously attached persistent disk. We are going to use a persistent disk mounted `bosh-workspace' directory as our working directory:

```
sudo mkdir -p /bosh-workspace
sudo /usr/share/google/safe_format_and_mount -m "mkfs.ext4 -F" /dev/sdb /bosh-workspace
sudo chmod 777 /bosh-workspace
```

Install Ruby 1.9.3 and all dependencies (be aware that BOSH only supports Ruby 1.9.3 actually):

```
sudo apt-get update
sudo apt-get -y install git-core libxslt-dev libxml2-dev libmysql-ruby libmysqlclient-dev libpq-dev
\curl -sSL https://get.rvm.io | bash -s stable --ruby=1.9.3
source /home/${USER}/.rvm/scripts/rvm
```

Build and install the BOSH gems located at the [Google Compute Engine BOSH CPI](https://github.com/cf-platform-eng/bosh-google-cpi/tree/google-cpi) github repo:

```
cd /bosh-workspace/
mkdir -p {apps,deployments,releases,stemcells,.ssh}
git clone -b google-cpi https://github.com/cf-platform-eng/bosh-google-cpi.git
cd bosh-google-cpi
bundle install --local
gem install bosh_cli_plugin_micro -v 1.2479.0
gem install vendor/cache/fog-1.22.0.gem
for gem in bosh-core bosh_common bosh-registry bosh_cpi bosh_aws_cpi bosh_google_cpi bosh_openstack_cpi bosh_vsphere_cpi blobstore_client agent_client bosh-monitor bosh_cli bosh_cli_plugin_aws bosh_cli_plugin_micro; do
    pushd $gem && gem build $gem.gemspec && gem install --local $gem*.gem && popd
done
```

Download the prebuilt BOSH stemcells (image templates) that we are going to use in our microBOSH:

```
cd /bosh-workspace/stemcells
wget http://storage.googleapis.com/bosh-stemcells/light-bosh-stemcell-2479-google-kvm-ubuntu-trusty.tgz
wget http://storage.googleapis.com/bosh-stemcells/light-bosh-stemcell-2479-google-kvm-centos.tgz
```

Download the microBOSH deployment manifests:

```
mkdir -p /bosh-workspace/deployments/microbosh
cd /bosh-workspace/deployments/microbosh
wget https://gist.githubusercontent.com/frodenas/92c953fc16c542e2e3ad/raw/micro_bosh.yml
```

Download the CloudFoundry deployment manifests:

```
mkdir -p /bosh-workspace/deployments/cf
cd /bosh-workspace/deployments/cf
wget https://gist.githubusercontent.com/frodenas/dfcf30b4a7ef51549775/raw/cf.yml
wget https://gist.githubusercontent.com/frodenas/6711234bab7a28d422b4/raw/cf-full.yml
```

Download an application example:

```
cd /bosh-workspace/apps/
git clone https://github.com/cloudfoundry-community/cf-env.git
```

Download and install the CloudFoundry CLI:

```
cd /tmp
wget https://cli.run.pivotal.io/stable?release=debian64 -O cf-cli_amd64.deb
sudo dpkg -i cf-cli_amd64.deb
```
