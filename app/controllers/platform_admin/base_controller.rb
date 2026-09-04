module PlatformAdmin
  class BaseController < ActionController::Base
    include PlatformAdminAuthentication

    allow_browser versions: :modern
  end
end
