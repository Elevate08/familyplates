# frozen_string_literal: true

require "pay"
require "stripe"
require "family_plates_saas/engine"

# The hosted edition of FamilyPlates. Loaded only by Gemfile.saas; an
# appliance bundle does not contain it, so nothing in here can run on a
# family's own server. A module of its own, not FamilyPlates::Saas, so that
# loading the gem does not define FamilyPlates ahead of the app's autoloader.
module FamilyPlatesSaas
end
