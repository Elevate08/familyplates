# frozen_string_literal: true

# Signing out tells the browser to forget what it kept for this site: the HTTP
# cache and, through "storage", the service worker's offline pages (Cache
# Storage), which "cache" alone leaves in place. "storage" also resets what the
# pages keep in localStorage (theme, grocery ticks, cook-mode progress).
# Browsers apply the header on the response they receive, redirects included,
# and only over HTTPS or localhost, which is also where a service worker runs.
#
# Operator sign-out sends CLEAR_CACHE only: the worker keeps no operator pages,
# and "storage" would wipe the offline data of a household the operator also
# belongs to in the same browser.
module ClearsSiteData
  extend ActiveSupport::Concern

  CLEAR_SITE_DATA = '"cache", "storage"'
  CLEAR_CACHE = '"cache"'

  private

  def clear_site_data(directives = CLEAR_SITE_DATA)
    response.headers["Clear-Site-Data"] = directives
  end
end
