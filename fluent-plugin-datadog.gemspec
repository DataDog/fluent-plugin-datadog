# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2018 Datadog, Inc.

# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-datadog"
  spec.version       = "0.13.0"
  spec.authors       = ["Datadog Solutions Team"]
  spec.email         = ["support@datadoghq.com"]
  spec.summary       = "Datadog output plugin for Fluent event collector"
  spec.homepage      = "http://datadoghq.com"
  spec.license       = "Apache-2.0"

  spec.files         = [".gitignore", "Gemfile", "LICENSE", "README.md", "Rakefile", "fluent-plugin-datadog.gemspec", "lib/fluent/plugin/out_datadog.rb"]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_runtime_dependency "fluentd", [">= 1", "< 2"]
  spec.add_runtime_dependency "net-http-persistent", '~> 3.1'

  spec.add_development_dependency "bundler", "~> 2.1"
  spec.add_development_dependency "test-unit", '~> 3.1'
  spec.add_development_dependency "rake", "~> 12.0"
  spec.add_development_dependency "yajl-ruby", "~> 1.2"
  spec.add_development_dependency 'webmock', "~> 3.5.0"
end
