# Fluentd output plugin for Datadog

This output plugin allows sending logs directly from Fluentd to Datadog - so you don't have to use a separate log shipper
if you don't wan't to.

## Pre-requirements

| fluent-plugin-datadog | Fluentd    | Ruby   |
|:--------------------------|:-----------|:-------|
| \>= 0.12.0               | \>= v1      | \>= 2.4 |
| < 0.12.0                   | \>= v0.12.0 | \>= 2.1 |

To add the plugin to your fluentd agent, use the following command:

    gem install fluent-plugin-datadog

If you installed the td-agent instead

    /usr/sbin/td-agent-gem install fluent-plugin-datadog

## Usage
### Configure the output plugin

To match events and send them to Datadog, simply add the following code to your configuration file.

HTTP example:

```xml
# Match events tagged with "datadog.**" and
# send them to Datadog
<match datadog.**>

  @type datadog
  @id awesome_agent
  api_key <your_api_key>

  # Optional
  include_tag_key true
  tag_key 'tag'

  # Optional parameters
  dd_source '<INTEGRATION_NAME>'
  dd_tags '<KEY1:VALUE1>,<KEY2:VALUE2>'
  dd_sourcecategory '<MY_SOURCE_CATEGORY>'

  # Optional http proxy
  http_proxy 'http://my-proxy.example'

  <buffer>
          @type memory
          flush_thread_count 4
          flush_interval 3s
          chunk_limit_size 5m
          chunk_limit_records 500
  </buffer>

</match>
```

After a restart of FluentD, any child events tagged with `datadog` are shipped to your platform.

### Validation
Let's make a simple test.

```bash
 curl -X POST -d 'json={"message":"hello Datadog from fluentd"}' http://localhost:8888/datadog.test
```

Produces the following event:

```javascript
{
    "message": "hello Datadog from fluentd"
}
```

### fluent-plugin-datadog properties
Let's go deeper on the plugin configuration.

As fluent-plugin-datadog is an output_buffer, you can set all output_buffer properties like it's describe in the [fluentd documentation](http://docs.fluentd.org/articles/output-plugin-overview#buffered-output-parameters "documentation").

|  Property   |  Description                                                             |  Default value |
|-------------|--------------------------------------------------------------------------|----------------|
| **api_key** | This parameter is required in order to authenticate your fluent agent. | nil |
| **use_json** | Event format, if true, the event is sent in json format. Othwerwise, in plain text. | true |
| **include_tag_key** | Automatically include the Fluentd tag in the record. | false |
| **tag_key** | Where to store the Fluentd tag. | "tag" |
| **timestamp_key** | Name of the attribute which will contain timestamp of the log event. If nil, timestamp attribute is not added. | "@timestamp" |
| **use_ssl** | If true, the agent initializes a secure connection to Datadog. In clear TCP otherwise. | true |
| **no_ssl_validation** | Disable SSL validation (useful for proxy forwarding) | false |
| **ssl_port** | Port used to send logs over a SSL encrypted connection to Datadog. If use_http is disabled, use 10516 for the US region and 443 for the EU region. | 443 |
| **max_retries** | The number of retries before the output plugin stops. Set to -1 for unlimited retries | -1 |
| **max_backoff** | The maximum time waited between each retry in seconds | 30 |
| **use_http** | Enable HTTP forwarding. If you disable it, make sure to change the port to 10514 or ssl_port to 10516 | true |
| **use_compression** | Enable log compression for HTTP | true |
| **compression_level** | Set the log compression level for HTTP (1 to 9, 9 being the best ratio) | 6 |
| **dd_source** | This tells Datadog what integration it is | nil |
| **dd_sourcecategory** | Multiple value attribute. Can be used to refine the source attribute | nil |
| **dd_tags** | Custom tags with the following format "key1:value1, key2:value2" | nil |
| **dd_hostname** | Used by Datadog to identify the host submitting the logs. | `hostname -f` |
| **service** | Used by Datadog to correlate between logs, traces and metrics. | nil |
| **port** | Proxy port when logs are not directly forwarded to Datadog and ssl is not used | 80 |
| **host** | Proxy endpoint when logs are not directly forwarded to Datadog | http-intake.logs.datadoghq.com |
| **http_proxy** | HTTP proxy, only takes effect if HTTP forwarding is enabled (`use_http`). Defaults to `HTTP_PROXY`/`http_proxy` env vars. | nil |

### Docker and Kubernetes tags

Tags in Datadog are critical to be able to jump from one part of the product to the other. Having the right metadata associated to your logs is therefore important to jump from the container view or any container metrics to the most related logs.

If your logs contain any of the following attributes, it will automatically be added as Datadog tags (with the same name as on your metrics) on your logs:

* kubernetes.container_image
* kubernetes.container_name
* kubernetes.namespace_name
* kubernetes.pod_name
* docker.container_id

If the Datadog Agent collect them automatically, FluentD requires a plugin for this. We recommend using [fluent-plugin-kubernetes_metadata_filter](https://github.com/fabric8io/fluent-plugin-kubernetes_metadata_filter) to collect Docker and Kubernetes metadata.

Configuration example:

```
# Collect metadata for logs tagged with "kubernetes.**"
<filter kubernetes.*>
  type kubernetes_metadata
</filter>
```

### Encoding

Datadog's API expects log messages to be encoded in UTF-8.
If some of your logs are encoded with a different encoding, we recommend using the [`record_modifier` filter plugin](https://github.com/repeatedly/fluent-plugin-record-modifier#char_encoding)
to encode these logs to UTF-8.

Configuration example:

```
# Change encoding of logs tagged with "datadog.**"
<filter datadog.**>
  @type record_modifier

  # change the encoding from the '<SOURCE_ENCODING>' of your logs to 'utf-8'
  char_encoding <SOURCE_ENCODING>:utf-8
</filter>
```

## Build

To build a new version of this plugin and push it to RubyGems:

- Update the version in the .gemspec file accordingly
- `rake build` to build the gem file
- `rake release` to push the new gem to RubyGems

**Note**: The latest command will fail without appropriate credentials configured. You can set those credentials by running the following command:

`curl -u <USERNAME> https://rubygems.org/api/v1/api_key.yaml > ~/.gem/credentials`, it will ask for your password.

