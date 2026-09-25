class SuspensionsController < ApplicationController
  allow_suspended_access only: :show

  def show
    @household = current_household
  end
end
