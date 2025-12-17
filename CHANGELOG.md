## 0.15.0
- Provide a configuration option to delete kubernetes and docker attributes from the log after the relevant information has been extracted into tags [#78](https://github.com/DataDog/fluent-plugin-datadog/pull/78) by [@sambart19].
- Fix launch.json and update readme [#76](https://github.com/DataDog/fluent-plugin-datadog/pull/76)
## 0.14.4
- Source `container_id` tag from kubernetes meta location [#67](https://github.com/DataDog/fluent-plugin-datadog/pull/67) by [@rlafferty](https://github.com/rlafferty)

## 0.14.3
- `timestamp_key` is ignored if empty, `nil`, or `null` as documented

## 0.14.2
 - Upgrade `net-http-persistent` dependency [#54](https://github.com/DataDog/fluent-plugin-datadog/pull/54) by [@javiercri](https://github.com/javiercri)

## 0.14.1
 - Use logger from PluginLoggerMixin [#50](https://github.com/DataDog/fluent-plugin-datadog/pull/50) by [@aglover-zendesk](https://github.com/aglover-zendesk)

## 0.14.0
 - Support Datadog v2 endpoints [#48](https://github.com/DataDog/fluent-plugin-datadog/pull/48)

## 0.13.0
 - Support HTTP proxies [#46](https://github.com/DataDog/fluent-plugin-datadog/pull/46)

## 0.12.1
 - Address persistent connection creation issues

## 0.12.0
 - Migrate to Fluentd v1 APIs
 - Enable HTTP forwarding by default
 - Enable gzip compression by default for HTTP
 - Add an option to disable SSL hostname verification
