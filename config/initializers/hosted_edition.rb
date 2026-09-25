# frozen_string_literal: true

# FAMILYPLATES_MODE=hosted on a bundle without the saas/ engine (an appliance
# image, or BUNDLE_GEMFILE forced to Gemfile) would serve hosted pages with no
# billing or operator console behind them. Refuse to boot instead.
Rails.application.config.after_initialize do
  FamilyPlates.require_hosted_edition! if FamilyPlates.config.hosted?
end
