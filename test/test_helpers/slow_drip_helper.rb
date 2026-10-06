require "socket"

# A real local server that answers with one byte every `interval` seconds, for
# tests of SafeHttpFetcher's overall deadline. OutboundUrlPolicy refuses
# 127.0.0.1, so the policy is stubbed to hand back a target pinned to it.
module SlowDripHelper
  # The server gives up after `for_seconds`, so a fetcher with no deadline ends
  # the test by failing an assertion instead of hanging it.
  def with_slow_drip_server(interval: 0.5, for_seconds: 8)
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    served = Thread.new do
      client = server.accept
      client.gets("\r\n\r\n")
      client.write "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 100000\r\n\r\n"
      (for_seconds / interval).to_i.times do
        client.write "x"
        sleep interval
      end
    rescue SystemCallError, IOError
      nil # the fetcher hung up, which is what the tests want
    ensure
      client&.close
    end

    original = OutboundUrlPolicy.method(:check!)
    OutboundUrlPolicy.define_singleton_method(:check!) do |url|
      OutboundUrlPolicy::Target.new(uri: URI.parse(url), address: "127.0.0.1")
    end

    yield "http://slow.test:#{port}/recipe"
  ensure
    OutboundUrlPolicy.define_singleton_method(:check!, original) if original
    served&.kill
    server&.close
  end

  # Shrinks the fetcher's total deadline so the test takes seconds, not 20.
  def with_fetch_deadline(seconds)
    had = SafeHttpFetcher.const_defined?(:TOTAL_TIMEOUT, false)
    original = SafeHttpFetcher::TOTAL_TIMEOUT if had
    SafeHttpFetcher.send(:remove_const, :TOTAL_TIMEOUT) if had
    SafeHttpFetcher.const_set(:TOTAL_TIMEOUT, seconds)
    yield
  ensure
    SafeHttpFetcher.send(:remove_const, :TOTAL_TIMEOUT)
    SafeHttpFetcher.const_set(:TOTAL_TIMEOUT, original) if had
  end

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
