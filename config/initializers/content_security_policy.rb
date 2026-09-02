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
    policy.img_src     :self, :data, :https
    policy.object_src  :none
    policy.script_src  :self
    policy.connect_src :self

    # style-src keeps 'unsafe-inline' deliberately. Avatar and theme colours are
    # per-record inline style attributes, and style-src-attr has no nonce
    # mechanism - allowing them means either this or moving every colour to a
    # custom property, which is a larger change than it is worth here. Style
    # injection is a far weaker primitive than script injection.
    policy.style_src   :self, :unsafe_inline

    policy.base_uri    :self
    policy.form_action :self
    policy.frame_ancestors :self
  end

  config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
  config.content_security_policy_nonce_directives = %w[script-src]
end
