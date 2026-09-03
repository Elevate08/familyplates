class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create destroy]

  def new
    redirect_to select_profile_path
  end

  def create
    redirect_to select_profile_path
  end

  def destroy
    terminate_session
    redirect_to select_profile_path, notice: "Signed out of kitchen profile.", status: :see_other
  end
end
