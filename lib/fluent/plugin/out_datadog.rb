# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2018 Datadog, Inc.

require "socket"
require "openssl"
require "yajl"
require "zlib"
require "fluent/plugin/output"

require_relative "version"

def nilish?(s)
  s.empty? || s == "nil" || s == "false" || s == "null"
end

class Fluent::DatadogOutput < Fluent::Plugin::Output
  class RetryableError < StandardError;
  end

  # Max limits for transport regardless of Fluentd buffer, respecting https://docs.datadoghq.com/api/?lang=bash#logs
  DD_MAX_BATCH_LENGTH = 500
  DD_MAX_BATCH_SIZE = 5000000
  DD_TRUNCATION_SUFFIX = "...TRUNCATED..."

  DD_DEFAULT_HTTP_ENDPOINT = "http-intake.logs.datadoghq.com"
  DD_DEFAULT_TCP_ENDPOINT = "intake.logs.datadoghq.com"

  helpers :compat_parameters

  DEFAULT_BUFFER_TYPE = "memory"

  # Register the plugin
  Fluent::Plugin.register_output('datadog', self)

  # Output settings
  config_param :include_tag_key, :bool, :default => false
  config_param :tag_key, :string, :default => 'tag'
  config_param :timestamp_key, :string, :default => '@timestamp'
  config_param :service, :string, :default => nil
  config_param :dd_sourcecategory, :string, :default => nil
  config_param :dd_source, :string, :default => nil
  config_param :dd_tags, :string, :default => nil
  config_param :dd_hostname, :string, :default => nil

  # Connection settings
  config_param :host, :string, :default => DD_DEFAULT_HTTP_ENDPOINT
  config_param :use_ssl, :bool, :default => true
  config_param :port, :integer, :default => 80
  config_param :ssl_port, :integer, :default => 443
  config_param :max_retries, :integer, :default => -1
  config_param :max_backoff, :integer, :default => 30
  config_param :use_http, :bool, :default => true
  config_param :use_compression, :bool, :default => true
  config_param :compression_level, :integer, :default => 6
  config_param :no_ssl_validation, :bool, :default => false
  config_param :http_proxy, :string, :default => nil
  config_param :force_v1_routes, :bool, :default => false

  # Format settings
  config_param :use_json, :bool, :default => true

  # API Settings
  config_param :api_key, :string, secret: true

  config_section :buffer do
    config_set_default :@type, DEFAULT_BUFFER_TYPE
  end

  def initialize
    super
  end

  def configure(conf)
    compat_parameters_convert(conf, :buffer)
    super
    return if @dd_hostname

    if not @use_http and @host == DD_DEFAULT_HTTP_ENDPOINT
      @host = DD_DEFAULT_TCP_ENDPOINT
    end

    # Set dd_hostname if not already set (can be set when using fluentd as aggregator)
    @dd_hostname = %x[hostname -f 2> /dev/null].strip
    @dd_hostname = Socket.gethostname if @dd_hostname.empty?

    @timestamp_key = nil if nilish?(@timestamp_key)
  end

  def multi_workers_ready?
    true
  end

  def formatted_to_msgpack_binary?
    true
  end

  def start
    super
    @client = new_client(log, @api_key, @use_http, @use_ssl, @no_ssl_validation, @host, @ssl_port, @port, @http_proxy, @use_compression, @force_v1_routes)
  end

  def shutdown
    super
  end

  def terminate
    super
    @client.close if @client
  end

  # This method is called when an event reaches Fluentd.
  def format(tag, time, record)
    # When Fluent::EventTime is msgpack'ed it gets converted to int with seconds
    # precision only. We explicitly convert it to floating point number, which
    # is compatible with Time.at below.
    record = enrich_record(tag, time.to_f, record)
    if @use_http
      record = Yajl.dump(record)
    else
      if @use_json
        record = "#{api_key} #{Yajl.dump(record)}"
      else
        record = "#{api_key} #{record}"
      end
    end
    [record].to_msgpack
  end


  # NOTE! This method is called by internal thread, not Fluentd's main thread.
  # 'chunk' is a buffer chunk that includes multiple formatted events.
  def write(chunk)
    begin
      if @use_http
        events = Array.new
        chunk.msgpack_each do |record|
          next if record.empty?
          events.push record[0]
        end
        process_http_events(events, @use_compression, @compression_level, @max_retries, @max_backoff, DD_MAX_BATCH_LENGTH, DD_MAX_BATCH_SIZE)
      else
        chunk.msgpack_each do |record|
          next if record.empty?
          process_tcp_event(record[0], @max_retries, @max_backoff, DD_MAX_BATCH_SIZE)
        end
      end
    rescue Exception => e
      log.error("Uncaught processing exception in datadog forwarder #{e.message}")
    end
  end

  # Process and send a set of http events. Potentially break down this set of http events in smaller batches
  def process_http_events(events, use_compression, compression_level, max_retries, max_backoff, max_batch_length, max_batch_size)
    batches = batch_http_events(events, max_batch_length, max_batch_size)
    batches.each do |batched_event|
      formatted_events = format_http_event_batch(batched_event)
      if use_compression
        formatted_events = gzip_compress(formatted_events, compression_level)
      end
      @client.send_retries(formatted_events, max_retries, max_backoff)
    end
  end

  # Process and send a single tcp event
  def process_tcp_event(event, max_retries, max_backoff, max_batch_size)
    if event.bytesize > max_batch_size
      event = truncate(event, max_batch_size)
    end
    @client.send_retries(event, max_retries, max_backoff)
  end

  # Group HTTP events in batches
  def batch_http_events(encoded_events, max_batch_length, max_request_size)
    batches = []
    current_batch = []
    current_batch_size = 0
    encoded_events.each_with_index do |encoded_event, i|
      current_event_size = encoded_event.bytesize
      # If this unique log size is bigger than the request size, truncate it
      if current_event_size > max_request_size
        encoded_event = truncate(encoded_event, max_request_size)
        current_event_size = encoded_event.bytesize
      end

      if (i > 0 and i % max_batch_length == 0) or (current_batch_size + current_event_size > max_request_size)
        batches << current_batch
        current_batch = []
        current_batch_size = 0
      end

      current_batch_size += encoded_event.bytesize
      current_batch << encoded_event
    end
    batches << current_batch
    batches
  end

  # Truncate events over the provided max length, appending a marker when truncated
  def truncate(event, max_length)
    if event.length > max_length
      event = event[0..max_length - 1]
      event[max(0, max_length - DD_TRUNCATION_SUFFIX.length)..max_length - 1] = DD_TRUNCATION_SUFFIX
      return event
    end
    event
  end

  def max(a, b)
    a > b ? a : b
  end

  # Format batch of http events
  def format_http_event_batch(events)
    "[#{events.join(',')}]"
  end

  # Enrich records with metadata such as service, tags or source
  def enrich_record(tag, time, record)
    if @dd_sourcecategory
      record["ddsourcecategory"] ||= @dd_sourcecategory
    end
    if @dd_source
      record["ddsource"] ||= @dd_source
    end
    if @dd_tags
      record["ddtags"] ||= @dd_tags
    end
    if @service
      record["service"] ||= @service
    end
    if @dd_hostname
      # set the record hostname to the configured dd_hostname only
      # if the record hostname is empty, ensuring having a hostname set
      # even if the record doesn't contain any.
      record["hostname"] ||= @dd_hostname
    end

    if @include_tag_key
      record[@tag_key] = tag
    end
    # If @timestamp_key already exists, we don't overwrite it.
    if @timestamp_key and record[@timestamp_key].nil? and time
      record[@timestamp_key] = Time.at(time).utc.iso8601(3)
    end

    container_tags = get_container_tags(record)
    unless container_tags.empty?
      if record["ddtags"].nil? || record["ddtags"].empty?
        record["ddtags"] = container_tags
      else
        record["ddtags"] = record["ddtags"] + "," + container_tags
      end
    end
    record
  end

  # Compress logs with GZIP
  def gzip_compress(payload, compression_level)
    gz = StringIO.new
    gz.set_encoding("BINARY")
    z = Zlib::GzipWriter.new(gz, compression_level)
    begin
      z.write(payload)
    ensure
      z.close
    end
    gz.string
  end

  # Build a new transport client
  def new_client(logger, api_key, use_http, use_ssl, no_ssl_validation, host, ssl_port, port, http_proxy, use_compression, force_v1_routes)
    if use_http
      DatadogHTTPClient.new logger, use_ssl, no_ssl_validation, host, ssl_port, port, http_proxy, use_compression, api_key, force_v1_routes
    else
      DatadogTCPClient.new logger, use_ssl, no_ssl_validation, host, ssl_port, port
    end
  end

  # Top level class for datadog transport clients, managing retries and backoff
  class DatadogClient
    def send_retries(payload, max_retries, max_backoff)
      backoff = 1
      retries = 0
      begin
        send(payload)
      rescue RetryableError => e
        if retries < max_retries || max_retries < 0
          @logger.warn("Retrying ", :exception => e, :backtrace => e.backtrace)
          sleep backoff
          backoff = 2 * backoff unless backoff > max_backoff
          retries += 1
          retry
        end
      end
    end

    def send(payload)
      raise NotImplementedError, "Datadog transport client should implement the send method"
    end

    def close
      raise NotImplementedError, "Datadog transport client should implement the close method"
    end
  end

  # HTTP datadog client
  class DatadogHTTPClient < DatadogClient
    require 'net/http'
    require 'net/http/persistent'

    def initialize(logger, use_ssl, no_ssl_validation, host, ssl_port, port, http_proxy, use_compression, api_key, force_v1_routes = false)
      @logger = logger
      protocol = use_ssl ? "https" : "http"
      port = use_ssl ? ssl_port : port
      if force_v1_routes
        @uri = URI("#{protocol}://#{host}:#{port.to_s}/v1/input/#{api_key}")
      else
        @uri = URI("#{protocol}://#{host}:#{port.to_s}/api/v2/logs")
      end
      proxy_uri = :ENV
      if http_proxy
        proxy_uri = URI.parse(http_proxy)
      elsif ENV['HTTP_PROXY'] || ENV['http_proxy']
        logger.info("Using HTTP proxy defined in `HTTP_PROXY`/`http_proxy` env vars")
      end
      logger.info("Starting HTTP connection to #{protocol}://#{host}:#{port.to_s} with compression " + (use_compression ? "enabled" : "disabled") + (force_v1_routes ? " using v1 routes" : " using v2 routes"))
      @client = Net::HTTP::Persistent.new name: "fluent-plugin-datadog-logcollector", proxy: proxy_uri
      @client.verify_mode = OpenSSL::SSL::VERIFY_NONE if no_ssl_validation
      unless force_v1_routes
        @client.override_headers["DD-API-KEY"] = api_key
        @client.override_headers["DD-EVP-ORIGIN"] = "fluent"
        @client.override_headers["DD-EVP-ORIGIN-VERSION"] = DatadogFluentPlugin::VERSION
      end
      @client.override_headers["Content-Type"] = "application/json"
      if use_compression
        @client.override_headers["Content-Encoding"] = "gzip"
      end
      if !@client.proxy_uri.nil?
        # Log the proxy settings as resolved by the HTTP client
        logger.info("Using HTTP proxy #{@client.proxy_uri.scheme}://#{@client.proxy_uri.host}:#{@client.proxy_uri.port} username: #{@client.proxy_uri.user ? "set" : "unset"}, password: #{@client.proxy_uri.password ? "set" : "unset"}")
      end
    end

    def send(payload)
      request = Net::HTTP::Post.new @uri.request_uri
      request.body = payload
      response = @client.request @uri, request
      res_code = response.code.to_i
      # on a backend error or on an http 429, retry with backoff
      if res_code >= 500 || res_code == 429
        raise RetryableError.new "Unable to send payload: #{res_code} #{response.message}"
      end
      if res_code >= 400
        @logger.error("Unable to send payload due to client error: #{res_code} #{response.message}")
      end
    end

    def close
      @client.shutdown
    end
  end

  # TCP Datadog client
  class DatadogTCPClient < DatadogClient
    require "socket"

    def initialize(logger, use_ssl, no_ssl_validation, host, ssl_port, port)
      @logger = logger
      @use_ssl = use_ssl
      @no_ssl_validation = no_ssl_validation
      @host = host
      @port = use_ssl ? ssl_port : port
    end

    def connect
      if @use_ssl
        @logger.info("Starting SSL connection #{@host} #{@port}")
        socket = TCPSocket.new @host, @port
        ssl_context = OpenSSL::SSL::SSLContext.new
        if @no_ssl_validation
          ssl_context.set_params({:verify_mode => OpenSSL::SSL::VERIFY_NONE})
        end
        ssl_context = OpenSSL::SSL::SSLSocket.new socket, ssl_context
        ssl_context.connect
        ssl_context
      else
        @logger.info("Starting plaintext connection #{@host} #{@port}")
        TCPSocket.new @host, @port
      end
    end

    def send(payload)
      begin
        @socket ||= connect
        @socket.puts(payload)
      rescue => e
        @socket.close rescue nil
        @socket = nil
        raise RetryableError.new "Unable to send payload: #{e.message}."
      end
    end

    def close
      @socket.close rescue nil
    end
  end

  # Collect docker and kubernetes tags for your logs using `filter_kubernetes_metadata` plugin,
  # for more information about the attribute names, check:
  # https://github.com/fabric8io/fluent-plugin-kubernetes_metadata_filter/blob/master/lib/fluent/plugin/filter_kubernetes_metadata.rb#L265

  def get_container_tags(record)
    [
        get_kubernetes_tags(record),
        get_docker_tags(record)
    ].compact.join(",")
  end

  def get_kubernetes_tags(record)
    if record.key?('kubernetes') and not record.fetch('kubernetes').nil?
      kubernetes = record['kubernetes']
      tags = Array.new
      tags.push("image_name:" + kubernetes['container_image']) unless kubernetes['container_image'].nil?
      tags.push("container_name:" + kubernetes['container_name']) unless kubernetes['container_name'].nil?
      tags.push("kube_namespace:" + kubernetes['namespace_name']) unless kubernetes['namespace_name'].nil?
      tags.push("pod_name:" + kubernetes['pod_name']) unless kubernetes['pod_name'].nil?
      tags.push("container_id:" + kubernetes['docker_id']) unless kubernetes['docker_id'].nil?
      return tags.join(",")
    end
    nil
  end

  def get_docker_tags(record)
    if record.key?('docker') and not record.fetch('docker').nil?
      docker = record['docker']
      tags = Array.new
      tags.push("container_id:" + docker['container_id']) unless docker['container_id'].nil?
      return tags.join(",")
    end
    nil
  end
end
