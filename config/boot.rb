# The hosted edition runs on its own bundle, which adds the saas/ engine.
# Anything else is the appliance, whose bundle does not contain it.
hosted = [ ENV["FAMILYPLATES_MODE"], ENV["APP_MODE"] ].compact.find { |mode| !mode.empty? } == "hosted" ||
  File.exist?(File.expand_path("../tmp/hosted.txt", __dir__))
ENV["BUNDLE_GEMFILE"] ||= File.expand_path(hosted ? "../Gemfile.saas" : "../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
