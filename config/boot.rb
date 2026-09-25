# The hosted edition runs on its own bundle, which adds the saas/ engine.
# Anything else is the appliance, whose bundle does not contain it. Where
# Gemfile.saas is absent (an appliance image), hosted mode falls through to
# the core bundle, and config/application.rb then refuses to
# boot with a message that says why.
hosted = [ ENV["FAMILYPLATES_MODE"], ENV["APP_MODE"] ].compact.find { |mode| !mode.empty? } == "hosted" ||
  File.exist?(File.expand_path("../tmp/hosted.txt", __dir__))
saas_gemfile = File.expand_path("../Gemfile.saas", __dir__)
ENV["BUNDLE_GEMFILE"] ||= hosted && File.exist?(saas_gemfile) ? saas_gemfile : File.expand_path("../Gemfile", __dir__)

require "bundler/setup" # Set up gems listed in the Gemfile.
require "bootsnap/setup" # Speed up boot time by caching expensive operations.
