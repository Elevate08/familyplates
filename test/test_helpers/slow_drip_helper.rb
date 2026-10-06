require "socket"
require "zlib"

# A real local server that answers with one byte every `interval` seconds, for
# tests of SafeHttpFetcher's overall deadline. OutboundUrlPolicy refuses
# 127.0.0.1, so the policy is stubbed to hand back a target pinned to it.
module SlowDripHelper
  # The server gives up after `for_seconds`, so a fetcher with no deadline ends the test by
  # failing an assertion instead of hanging it. `where` is the part of the response that
  # trickles: the body, the headers, or a gzip header whose decoder yields nothing.
  def with_slow_drip_server(where: :body, interval: 0.5, for_seconds: 8)
    server = TCPServer.new("127.0.0.1", 0)
    port = server.addr[1]
    drips = (for_seconds / interval).to_i
    drip = ->(client, bytes) { drips.times { client.write bytes; sleep interval } }
    served = Thread.new do
      client = server.accept
      client.gets("\r\n\r\n")
      case where
      when :body
        client.write "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: 100000\r\n\r\n"
        drip.call(client, "x")
      when :headers
        client.write "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\n"
        drip.call(client, "X-Pad: x\r\n")
        client.write "Content-Length: 2\r\nConnection: close\r\n\r\nok"
      when :gzip
        # Header with the FCOMMENT flag: a decoder yields nothing until the comment ends.
        client.write "HTTP/1.1 200 OK\r\nContent-Encoding: gzip\r\nConnection: close\r\n\r\n"
        client.write "\x1f\x8b\x08\x10\x00\x00\x00\x00\x00\x03".b
        drip.call(client, "x")
        client.write "\x00".b + Zlib.gzip("ok").b[10..]
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

  def monotonic_now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
end
