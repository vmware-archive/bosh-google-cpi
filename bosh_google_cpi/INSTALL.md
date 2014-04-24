# Installation Instructions

WARNING: This tutorial requires an experimental [Google Compute Engine BOSH CPI](https://github.com/cf-platform-eng/bosh-google-cpi/tree/google-cpi) not supported by [Pivotal](http://www.gopivotal.com/).

We are assuming you are familiar with BOSH and its terminology. If not, please take a look at the [BOSH documentation](http://docs.cloudfoundry.org/bosh/) before running this procedure.

## Setup the Google Cloud Platform environment

Before you can run this installation process, you must set up your [Google Cloud Platform](https://cloud.google.com/) environment as described here:

### Sign up and get credentials

1. [Sign up](https://developers.google.com/compute/docs/signup) and activate Google Compute Engine, if you haven't already.
1. Create a [service account](https://developers.google.com/console/help/new/#serviceaccounts) and secure store the downloaded PKCS #12 formatted private key.
1. Create [Interoperable Storage Access Keys](https://developers.google.com/storage/docs/migrating#keys) for [Google Cloud Storage](https://cloud.google.com/products/cloud-storage/).
1. [Download and Install](https://developers.google.com/compute/docs/gcutil) the gcutil command line tool.
1. If you didn't set your project ID in the [gcutil installation procedure]((https://developers.google.com/compute/docs/gcutil)), you can still set a default gcutil project ID by running:

```
gcutil getproject --project=<project-id> --cache_flag_values
```

## Prepare a jumpbox instance

Although not mandatory, it is a good idea to create an isolated vm instance to run this installation process. For your convenience, we have prepared a jumpbox image template with all dependencies included. But If you feel pretty confident with ruby and gem environments, or if you prefer to build the jumpbox instance from scratch, see then the [Advanced Notes](ADVANCED.md) document.

In this document we are assuming you are going to use an isolated vm instance from the prepared jumpbox image template.

### Create a image

Create a Google Compute Engine image on your own account from a raw disk image we have already published in Google Cloud Storage:

```
gcutil addimage bosh-jumpbox http://storage.googleapis.com/bosh-stemcells/bosh-jumpbox.tar.gz
```

**NOTE**: Creating the image can take a long time. If the above gcutil command timeouts (you see the message `WARNING: Timeout reached. insert of bosh-jumpbox has not yet completed`), you must wait until the image is in a **READY** status (`gcutil getimage bosh-jumpbox`) before proceeding with the next step.

### Create the jumbox instance

Start a new instance named `bosh-jumpbox` using the previously created image:

```
gcutil addinstance bosh-jumpbox --image=bosh-jumpbox --machine_type=n1-standard-1  --zone=us-central1-a \
    --auto_delete_boot_disk --wait_until_running --service_account_scopes=compute-rw,storage-full
```

**NOTE**: If you don't have yet a ssh key for Google Compute Engine, and the gcutil command asks you for a passphrase when creating a new ssh key, **leave it blank**, as BOSH doesn't support passphrase ssh keys actually.

Copy your SSH private key and the previously downloaded Google Compute Engine PKCS #12 formatted private key to the jumpbox instance:

```
gcutil push bosh-jumpbox <YOUR GOOGLE COMPUTE ENGINE PKCS12 FILE LOCATION> /bosh-workspace/.ssh/
gcutil push bosh-jumpbox ~/.ssh/google_compute_engine /bosh-workspace/.ssh/
```

SSH into the jumpbox instance:

```
gcutil ssh bosh-jumpbox
```

## Deploy microBOSH

### Prepare the Google Compute Engine environment

Reserve an Static IP addresses for the microBOSH instance:

```
gcutil reserveaddress --region us-central1 microbosh
```

BOSH requires some ports opened, so we need to add a new firewall and set the appropriate rules:

```
gcutil addfirewall bosh --description="BOSH" --target_tags="bosh" --allowed="tcp:22,tcp:4222,tcp:6868,tcp:25250,tcp:25555,tcp:25777,udp:53"
```

### Create a deployment manifest for microBOSH

Now we need to create a deployment manifest to spin up our microBOSH:

```
cd /bosh-workspace/deployments/microbosh
vi micro_bosh.yml
```

Update the contents of the micro_bosh.yml file filling your credentials:

```
<% require 'base64' %>
---
name: microbosh-google

logging:
  level: DEBUG

network:
  type: dynamic
  vip: <YOUR MICROBOSH STATIC IP>
  cloud_properties:
    tags:
      - bosh

resources:
  persistent_disk: 204800
  cloud_properties:
    instance_type: n1-standard-2

cloud:
  plugin: google
  properties:
    google:
      project: '<YOUR GOOGLE COMPUTE ENGINE PROJECT>'
      client_email: '<YOUR GOOGLE COMPUTE ENGINE CLIENT EMAIL>'
      pkcs12_key: '<%= Base64.encode64(File.new('/bosh-workspace/.ssh/<YOUR GOOGLE COMPUTE ENGINE PKCS12 FILE>', 'rb').read) %>'
      default_zone: 'us-central1-a'
      access_key_id: '<YOUR GOOGLE CLOUD STORAGE ACCESS KEY ID>'
      secret_access_key: '<YOUR GOOGLE CLOUD STORAGE SECRET ACCESS KEY>'
      ssh_user: <%= ENV['USER'] %>
      private_key: /bosh-workspace/.ssh/google_compute_engine

apply_spec:
  properties:
    dns:
      recursor: 8.8.8.8
    hm:
      resurrector_enabled: true
```

### Deploy microBOSH

Spin up the microBOSH instance using these commands:

```
cd /bosh-workspace/deployments
bosh micro deployment microbosh
bosh micro deploy /bosh-workspace/stemcells/light-bosh-stemcell-2479-google-kvm-ubuntu-trusty.tgz
```

### Test your microBOSH

If everything went well in the previous steps, you will have a microBOSH instance ready to target. You can now login to your microBOSH using the default credentials (`admin`/`admin`):

```
bosh target <YOUR MICROBOSH STATIC IP>
bosh status
```

Congratulations, you have deployed a microBOSH on Google Compute Engine! How about [deploying CloudFoundry](https://github.com/cf-platform-eng/bosh-google-cpi/blob/google-cpi/bosh_google_cpi/DEPLOYCF.md) now?
