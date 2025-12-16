# TestApp - Typical Fluentd Usage Example

This directory demonstrates an example of fluentd usage with the Datadog plugin - using configuration files and running Fluentd as a service.

## Files

- **`fluent.conf`** - Fluentd configuration file
- **`start_fluentd.sh`** - Script to start Fluentd with the configuration
- **`send_test_logs.sh`** - Script to send test logs via HTTP (bash)

## Quick Start

### 1. Set your Datadog API Key

```bash
export DD_API_KEY=your_api_key_here
```

### 2. Start Fluentd

```bash
./start_fluentd.sh
```

This starts Fluentd as a service with the configuration file. Fluentd will:
- Listen on HTTP port 8888 for log ingestion
- Listen on Forward port 24224 for Fluentd protocol
- Route logs matching `test.**` to Datadog

### 3. Send Test Logs

In another terminal:

```bash
# Using bash script
./send_test_logs.sh

# Or manually with curl
curl -X POST -d 'json={"message":"Hello from Fluentd"}' \
  http://localhost:8888/test.app
```

### 4. Verify Logs

Check your Datadog dashboard to see the logs appear. They should include:
- Original log fields
- Datadog metadata: `ddsource`, `ddtags`, `service`, `hostname`, `tag`, `@timestamp`
