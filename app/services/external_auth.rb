# frozen_string_literal: true

module ExternalAuth
  def self.provider_for(name)
    case name.to_s.downcase
    when "google" then Google
    when "apple" then Apple
    when "oidc" then Oidc
    else nil
    end
  end

  def self.enabled_providers
    [].tap do |list|
      list << "google" if Google.enabled?
      list << "apple" if Apple.enabled?
      list << "oidc" if Oidc.enabled?
    end
  end
end
