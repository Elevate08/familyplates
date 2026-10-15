# Terms of Service and Privacy Policy. Public, and readable by a suspended
# household too: they are what a suspension points back to.
class LegalController < ApplicationController
  allow_unauthenticated_access only: %i[terms privacy]
  allow_suspended_access only: %i[terms privacy]

  def terms
  end

  def privacy
  end
end
