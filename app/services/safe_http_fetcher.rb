require "net/http"

# Fetches a user-supplied URL under OutboundUrlPolicy, re-checking every redirect
# hop and refusing to read an unbounded response into memory.
class SafeHttpFetcher
  Rejected = OutboundUrlPolicy::Rejected

  MAX_REDIRECTS = 5
  MAX_BYTES = 2.megabytes
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10
  WRITE_TIMEOUT = 10
  # One budget for the whole fetch, every redirect hop included. The timeouts above
  # apply per socket operation, so a server sending a byte every few seconds never trips
  # them and would hold the request thread (Puma has few) indefinitely. The deadline is
  # checked before each hop and after each chunk, so a single read can run past it by at
  # most READ_TIMEOUT.
  TOTAL_TIMEOUT = 20

  Result = Struct.new(:status, :location, :body, keyword_init: true) do
    def redirect? = status.between?(300, 399) && location.present?
  end

  def self.get(url, headers: {})
    new(url, headers: headers).get
  end

  # Returns status too, so import can tell a 403/429 block from a page with no recipe.
  def self.get_response(url, headers: {})
    new(url, headers: headers).get_response
  end

  def initialize(url, headers: {})
    @url = url
    @headers = headers
    @deadline = monotonic_now + TOTAL_TIMEOUT
  end

  def get
    get_response.body
  end

  def get_response
    url = @url
    seen = 0

    loop do
      check_deadline!
      target = OutboundUrlPolicy.check!(url)
      result = perform_request(target)

      return result unless result.redirect?

      seen += 1
      raise Rejected, "more than #{MAX_REDIRECTS} redirects" if seen > MAX_REDIRECTS

      # Re-check the hop. A private redirect is the usual bypass of a check on the typed URL.
      url = URI.join(target.uri, result.location).to_s
    end
  end

  private

  # Connect to the pinned address. Keep the hostname for SNI and Host so DNS is not resolved again.
  # The proxy address is nil, not the default :ENV, so http_proxy/https_proxy cannot
  # reroute the request through a host the address policy never checked.
  def perform_request(target)
    uri = target.uri
    http = Net::HTTP.new(uri.host, uri.port, nil)
    http.ipaddr = target.address
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = [ OPEN_TIMEOUT, time_left ].min
    http.read_timeout = [ READ_TIMEOUT, time_left ].min
    http.write_timeout = [ WRITE_TIMEOUT, time_left ].min

    http.start do |connection|
      request = Net::HTTP::Get.new(uri.request_uri, @headers)

      connection.request(request) do |response|
        return Result.new(
          status: response.code.to_i,
          location: response["location"],
          body: read_capped(response)
        )
      end
    end
  end

  # Stop at MAX_BYTES. Content-Length is not trusted.
  def read_capped(response)
    body = +""

    response.read_body do |chunk|
      body << chunk
      if body.bytesize > MAX_BYTES
        raise Rejected, "response exceeded #{MAX_BYTES} bytes"
      end
      check_deadline!
    end

    body
  end

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

  def time_left = [ @deadline - monotonic_now, 0.1 ].max

  # Timeout::Error is what RecipeScraper already reports as :timeout.
  def check_deadline!
    raise Timeout::Error, "fetch exceeded #{TOTAL_TIMEOUT}s" if monotonic_now >= @deadline
  end
end
