require "ipaddr"
require "resolv"
require "uri"

# Decides whether the application may make an HTTP request to a user-supplied
# URL. Recipe import hands us a URL typed by whoever is using the app, so the
# only safe posture is to decide by resolved address, never by hostname: a name
# an attacker controls can be pointed anywhere, including at this container's own
# network, the Docker bridge, or a cloud metadata service.
class OutboundUrlPolicy
  class Rejected < StandardError; end

  ALLOWED_SCHEMES = %w[http https].freeze

  # open-uri mixes its reader into URI::HTTP, URI::HTTPS *and* URI::FTP, so
  # ftp:// is a real third scheme that must be turned away here. (file:// is not
  # reachable that way — URI::File has no #open — but the allowlist covers it
  # regardless rather than relying on that.)
  BLOCKED_IPV4 = %w[
    0.0.0.0/8
    10.0.0.0/8
    100.64.0.0/10
    127.0.0.0/8
    169.254.0.0/16
    172.16.0.0/12
    192.0.0.0/24
    192.0.2.0/24
    192.168.0.0/16
    198.18.0.0/15
    198.51.100.0/24
    203.0.113.0/24
    224.0.0.0/4
    240.0.0.0/4
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  BLOCKED_IPV6 = %w[
    ::/128
    ::1/128
    64:ff9b::/96
    100::/64
    2001:db8::/32
    fc00::/7
    fe80::/10
    ff00::/8
  ].map { |cidr| IPAddr.new(cidr) }.freeze

  Target = Struct.new(:uri, :address, keyword_init: true)

  # Returns the URI paired with the single address the request must be pinned to,
  # or raises Rejected. Pinning matters: resolving once here and connecting to a
  # different answer later is the DNS-rebinding hole this is meant to close.
  def self.check!(url)
    uri = parse(url)

    unless ALLOWED_SCHEMES.include?(uri.scheme)
      raise Rejected, "scheme #{uri.scheme.inspect} is not allowed"
    end

    raise Rejected, "no host in #{url.inspect}" if uri.host.blank?

    addresses = resolve(uri.host)
    raise Rejected, "#{uri.host} did not resolve" if addresses.empty?

    # Every answer has to pass. Checking only the one we intend to use would let
    # a host that returns both a public and a private address through.
    addresses.each do |address|
      if (reason = rejection_reason(address))
        raise Rejected, "#{uri.host} resolves to #{address} (#{reason})"
      end
    end

    Target.new(uri: uri, address: addresses.first)
  end

  def self.parse(url)
    URI.parse(url.to_s.strip)
  rescue URI::InvalidURIError => e
    raise Rejected, "unparseable URL: #{e.message}"
  end
  private_class_method :parse

  def self.resolve(host)
    literal = IPAddr.new(host) rescue nil
    return [ literal.to_s ] if literal

    Resolv.getaddresses(host).uniq
  end

  def self.rejection_reason(address)
    ip = IPAddr.new(address)
    ip = ip.native if ip.ipv4_mapped?

    blocked = ip.ipv4? ? BLOCKED_IPV4 : BLOCKED_IPV6
    return "not a global unicast address" if blocked.any? { |range| range.include?(ip) }

    nil
  rescue IPAddr::Error
    "unparseable address"
  end
end
