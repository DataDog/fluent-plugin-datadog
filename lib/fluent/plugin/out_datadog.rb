# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2017 Datadog, Inc.

require 'socket'
require 'openssl'
require 'yajl'

class Fluent::DatadogOutput < Fluent::BufferedOutput
  class ConnectionFailure < StandardError; end

  # Register the plugin
  Fluent::Plugin.register_output('datadog', self)
  # Output settings
  config_param :use_json,           :bool,    :default => true
  config_param :include_tag_key,    :bool,    :default => false
  config_param :tag_key,            :string,  :default => 'tag'
  config_param :dd_sourcecategory,  :string,  :default => nil
  config_param :dd_source,          :string,  :default => nil
  config_param :dd_tags,            :string,  :default => nil

  # Connection settings
  config_param :host,           :string,  :default => 'intake.logs.datadoghq.com'
  config_param :use_ssl,        :bool,    :default => true
  config_param :port,           :integer, :default => 10514
  config_param :ssl_port,       :integer, :default => 10516
  config_param :max_retries,    :integer, :default => -1

  # API Settings
  config_param :api_key,  :string

  def initialize
    super
  end

  # Define `log` method for v0.10.42 or earlier
  unless method_defined?(:log)
    define_method("log") { $log }
  end

  def configure(conf)
    super
  end

  def new_client
    if @use_ssl
      context    = OpenSSL::SSL::SSLContext.new
      socket     = TCPSocket.new @host, @ssl_port
      ssl_client = OpenSSL::SSL::SSLSocket.new socket, context
      ssl_client.connect
      return ssl_client
    else
      return TCPSocket.new @host, @port
    end
  end

  def start
    super
    @my_mutex = Mutex.new
    @running = true
  end

  def shutdown
    super
    @running = false
    if @client
      @client.close
    end
  end

  # This method is called when an event reaches Fluentd.
  def format(tag, time, record)
    return [tag, record].to_msgpack
  end

  # NOTE! This method is called by internal thread, not Fluentd's main thread.
  # 'chunk' is a buffer chunk that includes multiple formatted events.
  def write(chunk)
    messages = Array.new
    log.trace "Datadog plugin: received chunck: #{chunk}"
    chunk.msgpack_each do |tag, record|
      next unless record.is_a? Hash
      next if record.empty?

      log.trace "Datadog plugin: received record: #{record}"

      if @dd_sourcecategory
        record["ddsourcecategory"] = @dd_sourcecategory
      end
      if @dd_source
        record["ddsource"] = @dd_source
      end
      if @dd_tags
        record["ddtags"] = @dd_tags
      end
      if @include_tag_key
        record[@tag_key] = tag
      end
      if @use_json
        messages.push "#{api_key} " + Yajl.dump(record) + "\n"
      else
        next unless record.has_key? "message"
        messages.push "#{api_key} " + record["message"].strip + "\n"
      end
    end
    send_to_datadog(messages)
  end

  def send_to_datadog(events)
    @my_mutex.synchronize do
      log.trace "Sending nb_event=#{events.size} events to Datadog"

      events.each do |event|
        log.trace "Datadog plugin: about to send event=#{event}"
        retries = 0
        begin
          log.info "New attempt to Datadog attempt=#{retries}" if retries > 0
          @client ||= new_client
          @client.write(event)
        rescue => e
          if retries < @max_retries || @max_retries == -1
            # Restart a new connection
            @client.close rescue nil
            @client = nil
            a_couple_of_seconds = retries ** 2
            a_couple_of_seconds = 30 unless a_couple_of_seconds < 30
            retries += 1
            log.warn "Could not push event to Datadog, attempt=#{retries} max_attempts=#{max_retries} wait=#{a_couple_of_seconds}s error=#{e}"
            sleep a_couple_of_seconds
            retry
          end
          raise ConnectionFailure, "Could not push event to Datadog after #{retries} retries, #{e}"
        end
      end
    end
  end

end
