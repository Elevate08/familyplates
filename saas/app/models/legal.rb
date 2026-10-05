# The hosted service's legal documents. Bump TERMS_VERSION whenever the Terms
# of Service change materially; each user's accepted version is on their row.
module Legal
  TERMS_VERSION = "2026-09-25"
  PRIVACY_VERSION = "2026-09-25"

  def self.effective_date
    Date.iso8601(TERMS_VERSION).strftime("%B %-d, %Y")
  end
end
