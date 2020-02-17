require "fluent/test"
require "fluent/test/helpers"
require "fluent/test/driver/output"
require "fluent/plugin/out_datadog"

class FileOutputTest < Test::Unit::TestCase
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
        api_key = foo
      ])
      assert_not_nil plugin
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
end