#!/bin/bash
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2018 Datadog, Inc.

# Script to send test logs to Fluentd via HTTP
# This demonstrates typical usage - sending logs to Fluentd's HTTP endpoint

FLUENTD_URL="${FLUENTD_URL:-http://localhost:8888}"
TAG="${TAG:-test.app}"

echo "Sending test logs to Fluentd at ${FLUENTD_URL}"
echo "Tag: ${TAG}"
echo ""

# Send test log 1
echo "Sending log 1: Test message"
curl -X POST -d 'json={"message":"Test log message from TestApp","level":"info","user":"test_user","action":"test_action"}' \
  "${FLUENTD_URL}/${TAG}"

echo ""
echo ""

# Send test log 2
echo "Sending log 2: Debug message"
curl -X POST -d 'json={"message":"Another test message","level":"debug","component":"test_component","status":"success"}' \
  "${FLUENTD_URL}/${TAG}"

echo ""
echo ""

# Send test log 3
echo "Sending log 3: Error simulation"
curl -X POST -d 'json={"message":"Error simulation","level":"error","error_code":"TEST_ERROR","stack_trace":"test_stack_trace"}' \
  "${FLUENTD_URL}/${TAG}"

echo ""
echo ""
echo "Check Fluentd output or Datadog dashboard to verify logs were received."

