# Unless explicitly stated otherwise all files in this repository are licensed
# under the Apache License Version 2.0.
# This product includes software developed at Datadog (https://www.datadoghq.com/).
# Copyright 2017 Datadog, Inc.

# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)

Gem::Specification.new do |spec|
  spec.name          = "fluent-plugin-datadog"
  spec.version       = "0.9.5"
  spec.authors       = ["Datadog Solutions Team"]
  spec.email         = ["support@datadoghq.com"]
  spec.summary       = "Datadog output plugin for Fluent event collector"
  spec.homepage      = "http://datadoghq.com"
  spec.license       = "Apache License 2.0"

  spec.files         = [".gitignore", "Gemfile", "LICENSE", "README.md", "Rakefile", "fluent-plugin-datadog.gemspec", "lib/fluent/plugin/out_datadog.rb"]
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.5"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "yajl-ruby", "~> 1.2"
end
