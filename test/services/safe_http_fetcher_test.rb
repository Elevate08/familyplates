require "test_helper"

class SafeHttpFetcherTest < ActiveSupport::TestCase
  include SlowDripHelper

  # Stands in for the network. Each entry is the canned reply for one hop, so a
  # redirect chain can be exercised without a server - and without giving the
  # test a way to accidentally reach one.
  class ScriptedFetcher < SafeHttpFetcher
    attr_reader :visited

    def initialize(url, replies:)
      super(url)
      @replies = replies
      @visited = []
    end

    private

    def perform_request(target)
      @visited << [ target.uri.to_s, target.address ]
      @replies.shift or raise "ScriptedFetcher ran out of replies for #{target.uri}"
    end
  end

  def redirect_to(location)
    SafeHttpFetcher::Result.new(status: 302, location: location, body: "")
  end

  def ok(body)
    SafeHttpFetcher::Result.new(status: 200, location: nil, body: body)
  end

  test "refuses a blocked target before any request is made" do
    fetcher = ScriptedFetcher.new("http://169.254.169.254/latest/meta-data/", replies: [ ok("secrets") ])

    assert_raises(OutboundUrlPolicy::Rejected) { fetcher.get }
    assert_empty fetcher.visited, "nothing may be requested once the policy says no"
  end

  test "follows a redirect between public addresses" do
    fetcher = ScriptedFetcher.new(
      "http://93.184.216.34/old",
      replies: [ redirect_to("http://93.184.216.35/new"), ok("<html>recipe</html>") ]
    )

    assert_equal "<html>recipe</html>", fetcher.get
    assert_equal 2, fetcher.visited.length
  end

  test "re-checks each redirect hop, so a public host cannot bounce into private space" do
    fetcher = ScriptedFetcher.new(
      "http://93.184.216.34/start",
      replies: [ redirect_to("http://10.0.0.1/internal"), ok("internal data") ]
    )

    error = assert_raises(OutboundUrlPolicy::Rejected) { fetcher.get }

    assert_match(/10\.0\.0\.1/, error.message)
    assert_equal 1, fetcher.visited.length, "the private hop must never be requested"
  end

  test "re-checks a redirect to the metadata service" do
    fetcher = ScriptedFetcher.new(
      "http://93.184.216.34/start",
      replies: [ redirect_to("http://169.254.169.254/latest/meta-data/"), ok("creds") ]
    )

    assert_raises(OutboundUrlPolicy::Rejected) { fetcher.get }
    assert_equal 1, fetcher.visited.length
  end

  test "resolves a relative redirect against the hop it came from" do
    fetcher = ScriptedFetcher.new(
      "http://93.184.216.34/recipes/old",
      replies: [ redirect_to("/recipes/new"), ok("moved") ]
    )

    assert_equal "moved", fetcher.get
    assert_equal "http://93.184.216.34/recipes/new", fetcher.visited.last.first
  end

  test "gives up on a redirect loop" do
    replies = Array.new(SafeHttpFetcher::MAX_REDIRECTS + 2) { redirect_to("http://93.184.216.34/again") }
    fetcher = ScriptedFetcher.new("http://93.184.216.34/start", replies: replies)

    error = assert_raises(OutboundUrlPolicy::Rejected) { fetcher.get }

    assert_match(/redirects/, error.message)
    assert_operator fetcher.visited.length, :<=, SafeHttpFetcher::MAX_REDIRECTS + 1
  end

  test "stops reading a response that exceeds the size cap" do
    oversized = Object.new
    def oversized.read_body
      loop { yield "x" * 64.kilobytes }
    end

    fetcher = SafeHttpFetcher.new("http://93.184.216.34/huge")

    error = assert_raises(OutboundUrlPolicy::Rejected) do
      fetcher.send(:read_capped, oversized)
    end
    assert_match(/exceeded/, error.message)
  end

  test "reads a response that fits under the cap" do
    small = Object.new
    def small.read_body
      yield "<html>"
      yield "recipe"
      yield "</html>"
    end

    fetcher = SafeHttpFetcher.new("http://93.184.216.34/small")

    assert_equal "<html>recipe</html>", fetcher.send(:read_capped, small)
  end

  test "cuts off a response that trickles in slower than the total deadline" do
    with_fetch_deadline(2) do
      with_slow_drip_server(interval: 0.5) do |url|
        started = monotonic_now

        assert_raises(Timeout::Error) { SafeHttpFetcher.get(url) }

        elapsed = monotonic_now - started
        assert_operator elapsed, :>=, 1.5, "it should have read until the deadline, not given up early"
        assert_operator elapsed, :<, 4, "the deadline must cover the whole fetch, not each read"
      end
    end
  end

  test "the total deadline spans every redirect hop" do
    fetcher = nil
    with_fetch_deadline(1) do
      fetcher = ScriptedFetcher.new(
        "http://93.184.216.34/a",
        replies: [ redirect_to("http://93.184.216.34/b"), ok("late") ]
      )
      fetcher.define_singleton_method(:perform_request) do |target|
        sleep 1.2
        super(target)
      end

      assert_raises(Timeout::Error) { fetcher.get }
    end
    assert_equal 1, fetcher.visited.length, "no hop may start once the deadline has passed"
  end

  test "environment proxies are not used for the pinned connection" do
    received = nil
    fake_class = Class.new(RuntimeError)
    original = Net::HTTP.method(:new)
    Net::HTTP.define_singleton_method(:new) do |*args, **kwargs|
      received = args
      raise fake_class, "stop before any network use"
    end

    begin
      with_env("http_proxy" => "http://127.0.0.1:9", "https_proxy" => "http://127.0.0.1:9",
               "HTTP_PROXY" => "http://127.0.0.1:9", "HTTPS_PROXY" => "http://127.0.0.1:9") do
        assert_raises(fake_class) { SafeHttpFetcher.new("http://93.184.216.34/").get }
      end
    ensure
      Net::HTTP.define_singleton_method(:new, original)
    end

    assert_equal 3, received.size, "the proxy address argument must be passed explicitly"
    assert_nil received[2], "a nil proxy address disables env proxies"
  end

  private

  def with_env(vars)
    old = vars.keys.index_with { |k| ENV[k] }
    vars.each { |k, v| ENV[k] = v }
    yield
  ensure
    old.each { |k, v| v ? ENV[k] = v : ENV.delete(k) }
  end
end
