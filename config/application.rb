require_relative "boot"

# Load local environment variables from .env files when present
begin
  require "dotenv"
  env = ENV["RAILS_ENV"] || ENV["RACK_ENV"] || "development"
  files = [
    File.expand_path("../.env.#{env}.local", __dir__),
    (File.expand_path("../.env.local", __dir__) unless env == "test"),
    File.expand_path("../.env.#{env}", __dir__),
    File.expand_path("../.env", __dir__)
  ].compact
  Dotenv.load(*files)
rescue LoadError
  # Dotenv not loaded
end

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module HomeMealPlanner
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
