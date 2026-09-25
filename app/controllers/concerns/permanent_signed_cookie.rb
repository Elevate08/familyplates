# frozen_string_literal: true

# Every long-lived signed cookie in this app uses the same flags. Secure
# follows the request: a flat true drops the cookie on a LAN with no TLS.
module PermanentSignedCookie
  extend ActiveSupport::Concern

  private

  def write_permanent_signed_cookie(name, value)
    cookies.signed.permanent[name] = {
      value: value,
      httponly: true,
      same_site: :lax,
      secure: request.ssl?
    }
  end
end
