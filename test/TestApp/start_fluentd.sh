#!/bin/bash
# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2018 Datadog, Inc.

# Script to start Fluentd with the Datadog plugin configuration
# This demonstrates typical Fluentd usage - running as a service with a config file

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/fluent.conf"

# Check if API key is set
if [ -z "$DD_API_KEY" ]; then
  echo "Warning: DD_API_KEY environment variable is not set."
  echo "Please set it before starting Fluentd:"
  echo "  export DD_API_KEY=your_api_key_here"
  echo ""
  echo "Or edit fluent.conf and replace YOUR_API_KEY_HERE with your actual API key"
  echo ""
  if [ -t 0 ]; then
    # Only prompt if running interactively
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      exit 1
    fi
  else
    echo "Non-interactive mode: Continuing with placeholder API key"
  fi
fi

# Replace API key in config if DD_API_KEY is set
if [ -n "$DD_API_KEY" ]; then
  TEMP_CONFIG=$(mktemp)
  sed "s/YOUR_API_KEY_HERE/$DD_API_KEY/g" "$CONFIG_FILE" > "$TEMP_CONFIG"
  CONFIG_FILE="$TEMP_CONFIG"
  trap "rm -f $TEMP_CONFIG" EXIT
fi

echo "Starting Fluentd with configuration: ${SCRIPT_DIR}/fluent.conf"
echo "HTTP endpoint: http://localhost:8888"
echo "Forward endpoint: localhost:24224"
echo ""
echo "Press Ctrl+C to stop Fluentd"
echo ""

# Start Fluentd
bundle exec fluentd -c "$CONFIG_FILE" -v

