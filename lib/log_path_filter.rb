# frozen_string_literal: true

# Bearer tokens travel in the URL path (calendar feeds, profile transfers), and
# Rails::Rack::Logger writes the path into "Started GET ...". filter_parameters
# only covers params, not the path. Mask swaps the token for [FILTERED] while
# the logger runs; Restore, placed right after it, puts the real path back so
# routing, and every client URL, are unchanged.
#
# Two layers cover the Rails log. Mask/Restore keep the token out of the
# request line. RedactingFormatter redacts every line as it is formatted, so a
# token inside an exception message is stored as [FILTERED] rather than scrubbed
# later. kamal-proxy's own request log is not covered: it still records these
# paths, an accepted risk while that log stays on the host (FP-APPSEC-012, see
# saas/test/lib/kamal_destinations_test.rb).
module LogPathFilter
  ORIGINAL_KEY = "familyplates.original_path_info"
  FILTERED = "[FILTERED]"
  FILTERED_PATHS = [
    %r{\A(/calendars/feed/)[^/?]+},
    %r{\A(/transfer/)[^/?]+}
  ].freeze

  # Unanchored versions for free text. Group 1 is the route prefix, group 2 the
  # secret segment; anything after the next slash (/members/ID) is kept. %2F
  # and escaped slashes are matched so an encoded separator cannot hide it.
  SLASH = '(?:/|%2[Ff]|\\\\/)'
  TEXT_PATH_PATTERN = %r{(#{SLASH}calendars#{SLASH}feed#{SLASH}|#{SLASH}transfer#{SLASH})([^/\s"'?&\\]+)}
  TEXT_QUERY_PATTERN = /(?<![A-Za-z0-9_])((?:feed_token|calendar_token|token)(?:=|%3[Dd]))[^&\s"'\\]*/

  def self.filter(path)
    FILTERED_PATHS.reduce(path.to_s) { |result, pattern| result.sub(pattern, "\\1#{FILTERED}") }
  end

  # Unanchored: redacts a token wherever it appears in a log message.
  def self.redact(text)
    text.to_s.gsub(TEXT_PATH_PATTERN) { "#{$1}#{FILTERED}" }.gsub(TEXT_QUERY_PATTERN) { "#{$1}#{FILTERED}" }
  end

  # Extended onto a logger's own formatter (so TaggedLogging keeps working);
  # redacts the finished line before the logger writes it.
  module RedactingFormatter
    def call(severity, timestamp, progname, msg)
      LogPathFilter.redact(super)
    end
  end

  def self.install(logger)
    targets = logger.respond_to?(:broadcasts) ? logger.broadcasts : [ logger ]
    targets.each do |target|
      formatter = target.formatter
      next if formatter.nil? || formatter.singleton_class.include?(RedactingFormatter)

      formatter.extend(RedactingFormatter)
    end
  end

  class Mask
    def initialize(app)
      @app = app
    end

    def call(env)
      original = env["PATH_INFO"]
      filtered = LogPathFilter.filter(original)
      return @app.call(env) if filtered == original

      env[ORIGINAL_KEY] = original
      env["PATH_INFO"] = filtered
      begin
        @app.call(env)
      ensure
        env["PATH_INFO"] = original
      end
    end
  end

  class Restore
    def initialize(app)
      @app = app
    end

    def call(env)
      original = env.delete(ORIGINAL_KEY)
      env["PATH_INFO"] = original if original
      @app.call(env)
    end
  end
end
