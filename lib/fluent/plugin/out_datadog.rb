require 'socket'
require 'openssl'
require 'yajl'

class Fluent::DatadogOutput < Fluent::BufferedOutput
  class ConnectionFailure < StandardError; end

  # Register the plugin
  Fluent::Plugin.register_output('datadog', self)
  # Output settings
  config_param :use_json,       :bool,    :default => true
  config_param :include_tag_key,:bool,    :default => false
  config_param :tag_key,        :string,  :default => 'tag'

  # Connection settings
  config_param :host,           :string,  :default => 'intake.logs.datadoghq.com'
  config_param :use_ssl,        :bool,    :default => false
  config_param :port,           :integer, :default => 10514
  config_param :ssl_port,       :integer, :default => 10516
  config_param :max_retries,    :integer, :default => -1
  config_param :tcp_ping_rate,  :integer, :default => 10

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

  def client
    @_socket ||= if @use_ssl
      context    = OpenSSL::SSL::SSLContext.new
      socket     = TCPSocket.new @host, @ssl_port
      ssl_client = OpenSSL::SSL::SSLSocket.new socket, context
      ssl_client.connect
    else
      socket = TCPSocket.new @host, @port
    end

    return @_socket

  end

  #not used for now...
  def init_socket(socket)
    socket.setsockopt(Socket::SOL_SOCKET, Socket::SO_KEEPALIVE, true)

    begin
      socket.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPINTVL, 3)
      socket.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPCNT, 3)
      socket.setsockopt(Socket::SOL_TCP, Socket::TCP_KEEPIDLE, 10)
    rescue
      log.info "DatadogOutput: Fallback on socket options during initialization"
    end

    return socket
  end

  def start
    super
    @my_mutex = Mutex.new
    @running = true

    if @tcp_ping_rate > 0
      @timer = Thread.new do
        while @running do
          messages = Array.new
          messages.push("fp\n")
          send_to_datadog(messages)
          sleep(15)
        end
      end
    end

  end

  def shutdown
    super
    @running = false
    if @_socket
      @_socket.close()
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

      log.trace "Datadog plugin: received record: #{record}"

      if @include_tag_key
        record[@tag_key] = tag
      end
      if @use_json
        messages.push "#{api_key} " + Yajl.dump(record) + "\n"
      else
        next unless record.has_key? "message"
        messages.push "#{api_key} " + record["message"].rstrip() + "\n"
      end
    end
    send_to_datadog(messages)

  end

  def send_to_datadog(data)
    @my_mutex.synchronize do
      retries = 0
      begin
        log.trace "Send nb_event=#{data.size} events to Datadog"

        # Check the connectivity and write messages
        log.info "New attempt to Datadog attempt=#{retries}" if retries > 0

        retries = retries + 1
        data.each do |event|
          log.trace "Datadog plugin: about to send event=#{event}"
          client.write(event)
        end

        # Handle some failures
      rescue Errno::EHOSTUNREACH, Errno::ECONNREFUSED, Errno::ETIMEDOUT, Errno::EPIPE => e

        if retries < @max_retries || max_retries == -1
          @_socket = nil
          a_couple_of_seconds = retries ** 2
          a_couple_of_seconds = 30 unless a_couple_of_seconds < 30
          retries += 1
          log.warn "Could not push logs to Datadog, attempt=#{retries} max_attempts=#{max_retries} wait=#{a_couple_of_seconds}s error=#{e.message}"
          sleep a_couple_of_seconds
          retry
        end
        raise ConnectionFailure, "Could not push logs to Datadog after #{retries} retries, #{e.message}"
      end
    end
  end

end
