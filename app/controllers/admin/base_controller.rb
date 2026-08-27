module Admin
  class BaseController < ApplicationController
    before_action :require_admin

    private

    def require_admin
      unless current_family_member&.admin?
        redirect_to root_path, alert: "Access restricted to household organizers / admins."
      end
    end
  end
end
