# Fluentd output plugin for Datadog

It mainly contains a proper JSON formatter and a socket handler that
streams logs directly to Datadog - so no need to use a log shipper
if you don't wan't to.

## Pre-requirements

To add the plugin to your fluentd agent, use the following command:

    gem install fluent-plugin-datadog

If you installed the td-agent instead

    /usr/sbin/td-agent-gem install fluent-plugin-datadog

## Usage
### Configure the output plugin

To match events and send them to Datadog, simply add the following code to your configuration file.

TCP example:

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
  dd_tags '<KEY1:VALU1>,<KEY2:VALUE2>'
  dd_sourcecategory '<MY_SOURCE_CATEGORY>'
  dd_attributetags '<KEY1:ATTRIBUTE1>,<KEY2:ATTRIBUTE2.SUBATTRIBUTE>'

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
| **include_tag_key** | Automatically include tags in the record. | false |
| **tag_key** | Name of the tag attribute, if they are included. | "tag" |
| **timestamp_key** | Name of the attribute which will contain timestamp of the log event. If nil, timestamp attribute is not added. | "@timestamp" |
| **use_ssl** | If true, the agent initializes a secure connection to Datadog. In clear TCP otherwise. | true |
| **ssl_port** | Port used to send logs over a SSL encripted connection to Datadog (use 443 for the EU region) | 10516 |
| **max_retries** | The number of retries before the output plugin stops. Set to -1 for unlimited retries | -1 |
| **dd_source** | This tells Datadog what integration it is | nil |
| **dd_sourcecategory** | Multiple value attribute. Can be used to refine the source attribtue | nil |
| **dd_tags** | Custom tags with the following format "key1:value1, key2:value2" | nil |
| **dd_attributetags** | Custom tags which will be set from the value of the matched attribute with the following format "key1:attribute1, key2:attribute2" | nil |
| **port** | Proxy port when logs are not directly forwarded to Datadog and ssl is not used | 10514 |
| **host** | Proxy endpoint when logs are not directly forwarded to Datadog | intake.logs.datadoghq.com |

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
