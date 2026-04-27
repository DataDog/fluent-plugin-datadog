# Changelog

## 0.15.1 (2026-04-27)

### Ruby & Fluentd compatibility
- Added Ruby 4.x compatibility while maintaining Ruby 3.x support
- Migrated from deprecated `Fluent::BufferedOutput` (removed in Fluentd v1.0) to the modern `Fluent::Plugin::Output` API
- Added `prefer_buffered_processing true` to explicitly use the buffered `format`/`write` path
- Added `helpers :compat_parameters` and `compat_parameters_convert` for backward-compatible buffer config migration
- Added `require 'fluent/plugin/output'` so the plugin loads correctly outside Fluentd's boot process
- Moved `fluentd` from a development dependency to a runtime dependency in the gemspec

### Dependencies
- Replaced `yajl-ruby` (unmaintained native C extension, incompatible with Ruby 4.x) with Ruby stdlib `json`
- Replaced `Yajl.dump` with `record.to_json`
- Added `require 'time'` explicitly (stdlib) to ensure `Time#iso8601` is always available
- Removed deprecated `spec.test_files` from gemspec
- Updated license identifier from `"Apache License 2.0"` to SPDX `"Apache-2.0"`

### SSL / TLS improvements
- **`ssl_verify`** (default: `true`) — new config param to control SSL peer certificate and hostname verification. Enables `VERIFY_PEER` and `post_connection_check` when true. Set to `false` for environments with TLS-intercepting proxies, self-signed certificates, or IP address hosts.
  > **Breaking change from prior behaviour:** previous versions did not verify the peer certificate. If your deployment uses a TLS-intercepting proxy or a custom CA, set `ssl_verify false` or configure `ssl_ca_file`.
- **`ssl_ca_file`** (default: `nil`) — path to a custom CA bundle. When set, used instead of system default CA paths.
- Added `ssl_client.sync_close = true` to ensure the underlying TCP socket is closed with the SSL socket, preventing file descriptor leaks on reconnects
- Added `ssl_client.hostname = @host` (SNI) for correct virtual-host TLS handshakes
- Wrapped `ssl_client.connect` / `post_connection_check` in `begin/rescue` to close the socket on failure and prevent fd buildup during retry storms

### Shutdown & threading fixes
- `shutdown` now joins the `@timer` ping thread (with a `SHUTDOWN_TIMEOUT` of 10 seconds) before proceeding, and force-kills it if still alive, ensuring clean process exit
- `@client` is now set to `nil` after closing under `@my_mutex` in `shutdown`, preventing a late `send_to_datadog` call from reusing a closed socket
- Moved `super` in `shutdown` outside the mutex to prevent deadlock when Fluentd flushes buffered chunks during the shutdown lifecycle

### Logging
- Trace log no longer leaks the Datadog API key — replaced `event=#{event}` with `(#{event.bytesize} bytes)`

### Code quality
- Removed `$log` global fallback — modern Fluentd always provides `log`
- Replaced `not`/`and` keywords with `!`/`&&`
- Replaced `has_key?` with `key?`
- Fixed bare `api_key` / `max_retries` references to use `@api_key` / `@max_retries`
- Replaced `Array.new` with `[]`; removed redundant explicit `return` statements
- Updated `config_param` hash-rocket syntax to modern keyword syntax
