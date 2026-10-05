# frozen_string_literal: true

# Hosted users must have accepted the current Terms of Service to use a
# household (TermsAssent). A test user standing in for someone who signed up
# normally is created with `**accepted_terms`; one who never accepted is
# created without it.
module TermsAssentTestHelper
  def accepted_terms(version: TermsAssent.current_version, at: Time.current)
    { terms_version: version, terms_accepted_at: at }
  end

  # The fields a form that asks for the person's own acceptance submits.
  def terms_assent_params(version: TermsAssent.current_version)
    { accept_terms: "1", terms_version: version }
  end

  # Publishes `version` as the current Terms for the block.
  def with_current_terms_version(version)
    original = TermsAssent.method(:current_version)
    TermsAssent.define_singleton_method(:current_version) { version }
    yield
  ensure
    TermsAssent.define_singleton_method(:current_version, original)
  end
end

ActiveSupport.on_load(:active_support_test_case) { include TermsAssentTestHelper }
