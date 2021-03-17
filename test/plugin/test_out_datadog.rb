require "fluent/test"
require "fluent/test/helpers"
require "fluent/test/driver/output"
require "fluent/plugin/out_datadog"
require 'webmock/test_unit'

class FluentDatadogTest < Test::Unit::TestCase
  include Fluent::Test::Helpers

  def setup
    Fluent::Test.setup
  end

  def create_driver(conf = CONFIG)
    Fluent::Test::Driver::Output.new(Fluent::DatadogOutput).configure(conf)
  end

  def create_valid_subject
    create_driver(%[
        api_key = foo
      ]).instance
  end

  sub_test_case "configuration" do
    test "missing api key should throw an error" do
      begin
        create_driver("")
      rescue => e
        assert_kind_of Fluent::ConfigError, e
      end
    end

    test "api key should succeed" do
      plugin = create_driver(%[
        api_key foo
      ])
      assert_not_nil plugin
    end

    test "proxy is set correctly" do
      ENV["HTTP_PROXY"] = "http://env-proxy-host:123"
      plugin = create_driver(%[
        api_key foo
        proxy http://proxy-username:proxy-password@proxy-host.local:12345
      ])
      assert_not_nil plugin
      plugin.run do
        proxy_uri = plugin.instance.instance_variable_get(:@client).instance_variable_get(:@client).proxy_uri
        assert_equal "proxy-host.local", proxy_uri.host
        assert_equal 12345, proxy_uri.port
        assert_equal "proxy-username", proxy_uri.user
        assert_equal "proxy-password", proxy_uri.password
      end
      ENV["HTTP_PROXY"] = nil
    end

    test "proxy is pulled from env when not set in config" do
      ENV["HTTP_PROXY"] = "http://env-proxy-host:123"
      plugin = create_driver(%[
        api_key foo
      ])
      assert_not_nil plugin
      plugin.run do
        proxy_uri = plugin.instance.instance_variable_get(:@client).instance_variable_get(:@client).proxy_uri
        assert_equal "env-proxy-host", proxy_uri.host
        assert_equal 123, proxy_uri.port
        assert_equal nil, proxy_uri.user
        assert_equal nil, proxy_uri.password
      end
      ENV["HTTP_PROXY"] = nil
    end
  end

  sub_test_case "enrich_record" do
    test "should enrich records with tag if include_tag_key is specified" do
      plugin = create_driver(%[
        api_key foo
        include_tag_key true
      ]).instance
      tag = "foo"
      time = 12345
      record = {"message" => "bar", "@timestamp" => 33333}
      result = plugin.enrich_record(tag, time, record)
      assert_equal "foo", result["tag"]
      assert_equal 33333, result["@timestamp"]
    end

    test "should not set timestamp tag if it exists" do
      plugin = create_driver(%[
       api_key foo
       timestamp_key foo
      ]).instance
      time = 12345
      record = {"message" => "bar", "foo" => 33333}
      result = plugin.enrich_record(nil, time, record)
      assert_equal 33333, result["foo"]
    end

    test "should set timestamp tag if it does not exist" do
      plugin = create_driver(%[
        api_key foo
        timestamp_key foo
      ]).instance
      time = 12345
      record = {"message" => "bar"}
      result = plugin.enrich_record(nil, time, record)
      assert_equal "1970-01-01T03:25:45.000Z", result["foo"]
    end

    test "should add specific datadog attributes" do
      plugin = create_driver(%[
        api_key foo
        dd_sourcecategory dog
        dd_source apache
        service app
        dd_tags bob
      ]).instance
      time = 12345
      record = {"message" => "bar"}
      result = plugin.enrich_record(nil, time, record)
      assert_equal "dog", result["ddsourcecategory"]
      assert_equal "apache", result["ddsource"]
      assert_equal "app", result["service"]
      assert_equal "bob", result["ddtags"]
    end
  end

  sub_test_case "truncation" do
    test "truncate messages of the given length" do
      plugin = create_valid_subject
      input = "foobarfoobarfoobarfoobar"
      assert_equal 15, plugin.truncate(input, 15).length
    end

    test "replace the end of the message with a marker when truncated" do
      plugin = create_valid_subject
      input = "foobarfoobarfoobarfoobar"
      assert_true plugin.truncate(input, 15).end_with?("...TRUNCATED...")
    end

    test "return the marker if the message length is smaller than the marker length" do
      plugin = create_valid_subject
      input = "foobar"
      assert_equal "...TRUNCATED...", plugin.truncate(input, 1)
    end

    test "do nothing if the input length is smaller than the given length" do
      plugin = create_valid_subject
      input = "foobar"
      assert_equal "foobar", plugin.truncate(input, 15)
    end
  end

  sub_test_case "http events batching" do
    test "respect the batch length and create one batch of one event" do
      plugin = create_valid_subject
      input = [%{{"message => "dd"}}]
      assert_equal 1, plugin.batch_http_events(input, 1, 1000).length
    end

    test "respect the batch length and create two batches of one event" do
      plugin = create_valid_subject
      input = [%{{"message => "dd1"}}, %{{"message => "dd2"}}]
      actual = plugin.batch_http_events(input, 1, 1000)
      assert_equal 2, actual.length
      assert_equal %{{"message => "dd1"}}, actual[0][0]
      assert_equal %{{"message => "dd2"}}, actual[1][0]
    end

    test "respect the request size and create two batches of one event" do
      plugin = create_valid_subject
      input = ["dd1", "dd2"]
      actual = plugin.batch_http_events(input, 10, 3)
      assert_equal 2, actual.length
      assert_equal "dd1", actual[0][0]
      assert_equal "dd2", actual[1][0]
    end

    test "respect the request size and create two batches of two events" do
      plugin = create_valid_subject
      input = ["dd1", "dd2", "dd3", "dd4"]
      actual = plugin.batch_http_events(input, 6, 6)
      assert_equal 2, actual.length
      assert_equal "dd1", actual[0][0]
      assert_equal "dd2", actual[0][1]
      assert_equal "dd3", actual[1][0]
      assert_equal "dd4", actual[1][1]
    end

    test "truncate events whose length is bigger than the max request size" do
      plugin = create_valid_subject
      input = ["dd1", "foobarfoobarfoobar", "dd2"]
      actual = plugin.batch_http_events(input, 10, 3)
      assert_equal 3, actual.length
      assert_equal "dd1", actual[0][0]
      assert_equal "...TRUNCATED...", actual[1][0]
      assert_equal "dd2", actual[2][0]
    end
  end

  sub_test_case "http connection errors" do
    test "should retry when server is returning 5XX" do
      api_key = 'XXX'
      stub_dd_request_with_return_code(api_key, 500)
      payload = '{}'
      client = Fluent::DatadogOutput::DatadogHTTPClient.new Logger.new(STDOUT), false, false, "datadog.com", 443, 80, nil, false, api_key
      assert_raise(Fluent::DatadogOutput::RetryableError) do
        client.send(payload)
      end
    end

    test "should not retry when server is returning 4XX" do
      api_key = 'XXX'
      stub_dd_request_with_return_code(api_key, 400)
      payload = '{}'
      client = Fluent::DatadogOutput::DatadogHTTPClient.new Logger.new(STDOUT), false, false, "datadog.com", 443, 80, nil, false, api_key
      assert_nothing_raised do
        client.send(payload)
      end
    end
  end

  def stub_dd_request_with_return_code(api_key, return_code)
    stub_dd_request(api_key).
        to_return(status: return_code, body: "", headers: {})
  end

  def stub_dd_request_with_error(api_key, error)
    stub_dd_request(api_key).
        to_raise(error)
  end

  def stub_dd_request(api_key)
    stub_request(:post, "http://datadog.com/v1/input/#{api_key}").
        with(
            body: "{}",
            headers: {
                'Accept' => '*/*',
                'Accept-Encoding' => 'gzip;q=1.0,deflate;q=0.6,identity;q=0.3',
                'Connection' => 'keep-alive',
                'Content-Type' => 'application/json',
                'Keep-Alive' => '30',
                'User-Agent' => 'Ruby'
            })
  end
end
