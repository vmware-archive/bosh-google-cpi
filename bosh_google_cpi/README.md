# BOSH Google Compute Engine Cloud Provider Interface
# Copyright (c) 2014 Pivotal Software, Inc. All Rights Reserved.

For online documentation see: http://rubydoc.info/gems/bosh_google_cpi/

## CPI Options

These options are passed to the BOSH Google Compute Engine CPI when it is instantiated.

### BOSH Google Compute Engine CPI options

The BOSH CPI options are passed to the BOSH Google Compute Engine CPI by the BOSH director based on the settings in `director.yml`:

<table>
  <tr>
    <th>Option</th>
    <th>Required</th>
    <th>Type</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>project</td>
    <td>Y</td>
    <td>String</td>
    <td>Google Compute Engine project</td>
  </tr>
  <tr>
    <td>client_email</td>
    <td>Y</td>
    <td>String</td>
    <td>Google Compute Engine client email</td>
  </tr>
  <tr>
    <td>pkcs12_key</td>
    <td>Y</td>
    <td>String</td>
    <td>Google Compute Engine PKCS12 key (Base64 encoded - RFC 2045)</td>
  </tr>
  <tr>
    <td>default_zone</td>
    <td>Y</td>
    <td>String</td>
    <td>Google Compute Engine default Zone</td>
  </tr>
  <tr>
    <td>access_key_id</td>
    <td>Y</td>
    <td>String</td>
    <td>Google Cloud Storage access key id</td>
  </tr>
  <tr>
    <td>secret_access_key</td>
    <td>Y</td>
    <td>String</td>
    <td>Google Cloud Storage secret access key</td>
  </tr>
</table>

### BOSH Registry options

The BOSH Registry options are passed to the BOSH Google Compute Engine CPI by the BOSH director based on the settings in `director.yml`.

<table>
  <tr>
    <th>Option</th>
    <th>Required</th>
    <th>Type</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>endpoint</td>
    <td>Y</td>
    <td>String</td>
    <td>BOSH Registry URL</td>
  </tr>
  <tr>
    <td>user</td>
    <td>Y</td>
    <td>String</td>
    <td>BOSH Registry user</td>
  </tr>
  <tr>
    <td>password</td>
    <td>Y</td>
    <td>String</td>
    <td>BOSH Registry password</td>
  </tr>
</table>

### BOSH Agent options

The BOSH Agent options are passed to the BOSH Google Compute Engine CPI by the BOSH director based on the settings in `director.yml`.

## BOSH Network options

The BOSH Google Compute Engine CPI supports these networks types:

<table>
  <tr>
    <th>Type</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>dynamic</td>
    <td>To use DHCP assigned IPs by Google Compute Engine</td>
  </tr>
  <tr>
    <td>vip</td>
    <td>To use previously allocated Google Compute Engine Static IPs</td>
  </tr>
</table>

These options are specified under `cloud_properties` in the `networks` section of a BOSH deployment manifest and are only valid for `dynamic` networks:

<table>
  <tr>
    <th>Option</th>
    <th>Required</th>
    <th>Type</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>network_name</td>
    <td>N</td>
    <td>String</td>
    <td>The name of the Google Compute Engine network the instances should belong to. If not set, by default it will use the `default` network</td>
  </tr>
  <tr>
    <td>tags</td>
    <td>N</td>
    <td>Array</td>
    <td>A list of tags to apply to the instances belonging to the network. Useful if you want to apply firewall or routes rules based on tags.</td>
  </tr>
  <tr>
    <td>ephemeral_external_ip</td>
    <td>N</td>
    <td>Boolean</td>
    <td>If instances must have an ephemeral external IP. `false` by default</td>
  </tr>
  <tr>
    <td>ip_forwarding</td>
    <td>N</td>
    <td>Boolean</td>
    <td>If instances must have IP forwarding enabled. `false` by default</td>
  </tr>
  <tr>
    <td>target_pool</td>
    <td>N</td>
    <td>String</td>
    <td>The name of the Google Compute Engine target pool the instances belonging to the network should be added to</td>
  </tr>
</table>

## Resource pool options

These options are specified under `cloud_properties` in the `resource_pools` section of a BOSH deployment manifest:

<table>
  <tr>
    <th>Option</th>
    <th>Required</th>
    <th>Type</th>
    <th>Description</th>
  </tr>
  <tr>
    <td>instance_type</td>
    <td>Y</td>
    <td>String</td>
    <td>The name of the Google Compute Engine machine type the instances should belong to</td>
  </tr>
  <tr>
    <td>zone</td>
    <td>N</td>
    <td>String</td>
    <td>The name of the Google Compute Engine zone the instances should belong to</td>
  </tr>
  <tr>
    <td>automatic_restart</td>
    <td>N</td>
    <td>Boolean</td>
    <td>If the instances should be restarted automatically if they are terminated for non-user-initiated reasons (maintenance event, hardware failure, software failure, etc). `false` by default</td>
  </tr>
  <tr>
    <td>on_host_maintenance</td>
    <td>N</td>
    <td>String</td>
    <td>Instance behavior on infrastructure maintenance that may temporarily impact instance performance. Supported values are 'MIGRATE' (default) or 'TERMINATE'</td>
  </tr>
  <tr>
    <td>service_scopes</td>
    <td>N</td>
    <td>Array</td>
    <td>Authorization scope names (not alias) for your default service account that determine the level of access your instance has to other Google services. By default no scope is assigned to the instance</td>
  </tr>
</table>

## Example

This is a sample of how Google Compute Engine CPI specific properties are used in a BOSH deployment manifest:

    ---
    name: sample
    director_uuid: 38ce80c3-e9e9-4aac-ba61-97c676631b91

    ...

    networks:
      - name: default
        type: dynamic
        dns:
          - 8.8.8.8
          - 8.8.4.4
        cloud_properties:
          network_name: 'default'
          tags:
            - bosh
          ephemeral_external_ip: false
          ip_forwarding: false
          target_pool: 'my-load-balancer'
      - name: static
        type: vip
        cloud_properties: {}
    ...

    resource_pools:
      - name: common
        network: default
        size: 1
        stemcell:
          name: bosh-google-kvm-ubuntu
          version: latest
        cloud_properties:
          instance_type: 'n1-standard-1'
          zone: 'us-central1-a'
          automatic_restart: false
          on_host_maintenance: 'MIGRATE'
          service_scopes:
            - compute.readonly
            - devstorage.read_write
    ...

    properties:
      google:
        project: 'my-test-project'
        client_email: 'frodenas'
        pkcs12_key: !binary |-
        default_zone: 'us-central1-a'
        access_key_id: 'access_key_id'
        secret_access_key: 'secret_access_key'

    ...
