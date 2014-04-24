# Deploying CloudFoundry on Google Cloud Platform

WARNING: This tutorial requires an experimental [Google Compute Engine BOSH CPI](https://github.com/cf-platform-eng/bosh-google-cpi/tree/google-cpi) not supported by [Pivotal](http://www.gopivotal.com/).

We are assuming you followed the [BOSH Installation Instructions](https://github.com/cf-platform-eng/bosh-google-cpi/blob/google-cpi/bosh_google_cpi/INSTALL.md) and you have a microBOSH up and running.

## Setup the Google Cloud Platform environment

### SSH into the jumpbox instance

SSH into the jumpbox instance, if you haven't already:

```
gcutil ssh bosh-jumpbox
```

### Prepare the Google Compute Engine environment

Reserve the IP address that will be used by CloudFoundry:

```
cf_ip=$(gcutil reserveaddress --region us-central1 cloudfoundry | grep RESERVED | awk '{ print $8 }')
```

Create a Load Balancer (Target Pool and Forwarding Rule) to route incoming requests to the CloudFoundry routers:

```
gcutil addtargetpool cloudfoundry --description="CloudFoundry" --region us-central1
gcutil addforwardingrule cloudfoundry --description="CloudFoundry" --region us-central1 --target_pool cloudfoundry --port_range 80 --ip ${cf_ip}
```

CloudFoundry requires some ports opened, so we will need to add a new firewall and set the appropriate rules:

```
gcutil addfirewall cloudfoundry --description="CloudFoundry" --target_tags="cf" --allowed="tcp:80,tcp:443"
```

## Deploy CloudFoundry

### Upload a BOSH stemcell

We need to upload a BOSH stemcell (image template) first to our microBOSH director:

```
cd /bosh-workspace/stemcells
bosh upload stemcell light-bosh-stemcell-2479-google-kvm-ubuntu-trusty.tgz
```

### Upload the CloudFoundry release

Now we will upload the CloudFoundry release (a package that contains all the CloudFoundry bits):

```
cd /bosh-workspace/releases/cf-release
bosh upload release releases/cf-170.tgz
```

### Create a deployment manifest for CloudFoundry

Then we need to create a deployment manifest. We will use a [preexisting deployment manifest](https://gist.github.com/frodenas/dfcf30b4a7ef51549775) suitable for the Google Compute Engine BOSH CPI:

```
cd /bosh-workspace/deployments/cf
vi cf.yml
```

And we will modify some variables at the top of the file:

* `director_uuid = 'CHANGE-ME'`: replace `CHANGE-ME` with the UUID from `bosh status`
* `static_ip = 'CHANGE-ME'`: replace `CHANGE-ME` with the static IP we reserved previously (named `cloudfoundry`)

**NOTE**: The deployment manifest creates a small CloudFoundry environment that fits into the default Google Compute Engine quota. If your project quota allows you to spin more than 50 vCPUs, then you can use a [deployment manifest](https://gist.github.com/frodenas/6711234bab7a28d422b4) that creates a full CloudFoundry environment. For your convenience, there is a `cf-full.yml` file at the `/bosh-workspace/deployments/cf` directory.

### Deploy CloudFoundry

Deploy CloudFoundry using these commands:

```
cd /bosh-workspace/deployments/cf
bosh deployment cf.yml
bosh deploy
```

**NOTE**: Deploying CloudFoundry will take about 15 minutes.

## Test CloudFoundry

If everything went well in the previous steps, you will have a CloudFoundry environment ready to use.

### Login into CloudFoundry

Login into your CloudFoundry environment using the default credentials (`admin`/`c1oudc0wc1oudc0w`) and create a space:

```
cf api http://api.${cf_ip}.xip.io
cf login -u admin -p c1oudc0wc1oudc0w -o admin
cf create-space -o admin admin
cf target -o admin -s admin
```

### Pushing a sample application

Let's deploy now a sample application:

```
cd /bosh-workspace/apps/cf-env
cf push
```

That's all. Point your browser at `http://env.<YOUR CLOUDFOUNDRY STATIC IP>.xip.io` and you will see your application up and running!

Congratulations, you have deployed CloudFoundry on Google Compute Engine!
