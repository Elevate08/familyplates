module Admin
  class AccountsController < BaseController
    before_action :set_user

    def edit
    end

    def update
      if @user.update(user_params)
        redirect_to admin_root_path, notice: "Master account credentials updated successfully! 🔐"
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_user
      @user = current_user
    end

    def user_params
      p = params.require(:user).permit(:email_address, :password, :password_confirmation)
      p.delete(:password) if p[:password].blank?
      p.delete(:password_confirmation) if p[:password_confirmation].blank?
      p
    end
  end
end
