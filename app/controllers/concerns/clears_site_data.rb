# frozen_string_literal: true

# Signing out tells the browser to forget what it kept for this site: the HTTP
# cache and, through "storage", the service worker's offline pages (Cache
# Storage), which "cache" alone leaves in place. "storage" also resets what the
# pages keep in localStorage (theme, grocery ticks, cook-mode progress).
# Browsers apply the header on the response they receive, redirects included,
# and only over HTTPS or localhost, which is also where a service worker runs.
module ClearsSiteData
  extend ActiveSupport::Concern

  CLEAR_SITE_DATA = '"cache", "storage"'

  private

  def clear_site_data
    response.headers["Clear-Site-Data"] = CLEAR_SITE_DATA
  end
end
