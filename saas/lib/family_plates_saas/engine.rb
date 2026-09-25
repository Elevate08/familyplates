# frozen_string_literal: true

module FamilyPlatesSaas
  # Not isolated: the hosted controllers, models and route helpers keep the
  # names they had in the core app, so core views can link to them when the
  # engine is loaded. saas/config/routes.rb draws into the app's routes.
  class Engine < ::Rails::Engine
  end
end
