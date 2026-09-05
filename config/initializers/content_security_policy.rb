# A Content Security Policy. There was none at all before this - the generated
# file shipped commented out end to end - which is what turned the escaping bugs
# fixed earlier in this branch from bad into directly exploitable.
#
# script-src carries no 'unsafe-inline'. That is the point of the whole exercise:
# an injected <script> or event handler has nothing to authorise it. First-party
# inline scripts are allowed by nonce instead, which an injected payload cannot
# guess. Inline event handlers cannot be nonced at all, so all sixteen of them
# were converted to Stimulus actions to make this possible.
Rails.application.configure do
  config.content_security_policy do |policy|
    policy.default_src :self
    policy.font_src    :self, :data
    # blob: for the image preview on the recipe form, which shows a chosen file
    # via URL.createObjectURL before it is uploaded.
    policy.img_src     :self, :data, :blob, :https
    policy.object_src  :none
    policy.script_src  :self
    policy.connect_src :self, "https://checkout.stripe.com", "https://billing.stripe.com", "https://api.stripe.com"

    # style-src keeps 'unsafe-inline' deliberately. Avatar and theme colours are
    # per-record inline style attributes, and style-src-attr has no nonce
    # mechanism - allowing them means either this or moving every colour to a
    # custom property, which is a larger change than it is worth here. Style
    # injection is a far weaker primitive than script injection.
    policy.style_src   :self, :unsafe_inline

    policy.base_uri    :self

    # External form actions permitted for OAuth providers and Stripe Checkout redirects
    allowed_form_actions = [ :self, "https://accounts.google.com", "https://appleid.apple.com", "https://checkout.stripe.com", "https://billing.stripe.com" ]
    if (oidc_url = ENV["OIDC_ISSUER"].presence || ENV["OIDC_AUTH_URL"].presence)
      begin
        uri = URI.parse(oidc_url)
        allowed_form_actions << "#{uri.scheme}://#{uri.host}#{":#{uri.port}" if uri.port && ![ 80, 443 ].include?(uri.port)}"
      rescue URI::InvalidURIError
        # Ignore malformed URI
      end
    end
    policy.form_action(*allowed_form_actions)

    policy.frame_ancestors :self
  end

  # The nonce has to satisfy two constraints at once.
  #
  # It must exist before a session does: request.session.id, which the generated
  # initializer suggests, is nil until something is written to the session, so on
  # /select_profile it emitted a bare "nonce-" matching nothing.
  #
  # And it must stay the same across a Turbo Drive navigation. Turbo replaces the
  # body without reloading the document, so the policy still being enforced is the
  # one the *first* page arrived with. A fresh random nonce per request means the
  # scripts Turbo injects carry the new page's nonce while the browser is checking
  # against the old one, and every one of them is refused.
  #
  # Storing it in the session satisfies both: writing forces the session into
  # existence, and the value then holds for as long as the visitor is browsing.
  config.content_security_policy_nonce_generator = lambda do |request|
    request.session[:csp_nonce] ||= SecureRandom.base64(16)
  end
  config.content_security_policy_nonce_directives = %w[script-src]
end
