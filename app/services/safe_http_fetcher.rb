require "net/http"

# Fetches a user-supplied URL under OutboundUrlPolicy, re-checking every redirect
# hop and refusing to read an unbounded response into memory.
class SafeHttpFetcher
  Rejected = OutboundUrlPolicy::Rejected

  MAX_REDIRECTS = 5
  MAX_BYTES = 2.megabytes
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  Result = Struct.new(:status, :location, :body, keyword_init: true) do
    def redirect? = status.between?(300, 399) && location.present?
  end

  def self.get(url, headers: {})
    new(url, headers: headers).get
  end

  # Same request, but the caller keeps the final status. Recipe import needs it
  # to tell "the site turned us away" (403/429 anti-bot) from "the page was
  # there but had no recipe in it", which are different messages to a user.
  def self.get_response(url, headers: {})
    new(url, headers: headers).get_response
  end

  def initialize(url, headers: {})
    @url = url
    @headers = headers
  end

  def get
    get_response.body
  end

  def get_response
    url = @url
    seen = 0

    loop do
      target = OutboundUrlPolicy.check!(url)
      result = perform_request(target)

      return result unless result.redirect?

      seen += 1
      raise Rejected, "more than #{MAX_REDIRECTS} redirects" if seen > MAX_REDIRECTS

      # A redirect to a private address is the standard way around a check that
      # only looks at the URL the user typed, so the new location goes back
      # through the policy on the next pass rather than being followed here.
      url = URI.join(target.uri, result.location).to_s
    end
  end

  private

  # The network seam. Connects to the address the policy pinned, while leaving
  # the hostname in place for TLS SNI and the Host header, so nothing re-resolves
  # between the check and the connection.
  def perform_request(target)
    uri = target.uri
    http = Net::HTTP.new(uri.host, uri.port)
    http.ipaddr = target.address
    http.use_ssl = uri.scheme == "https"
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT

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

  # Streams and stops at the cap, so a response that never ends cannot exhaust
  # memory. Content-Length is not trusted; it is trivially wrong or absent.
  def read_capped(response)
    body = +""

    response.read_body do |chunk|
      body << chunk
      if body.bytesize > MAX_BYTES
        raise Rejected, "response exceeded #{MAX_BYTES} bytes"
      end
    end

    body
  end
end
