module Admin
  class FamilyMembersController < BaseController
    before_action :set_family_member, only: %i[edit update destroy reset_pin]

    def index
      @family_members = current_household.family_members.order(:created_at)
      @new_member = current_household.family_members.build(role: "member", avatar_color: "#3B82F6", avatar_icon: "chef-hat")
    end

    def create
      @family_member = current_household.family_members.build(family_member_params)
      if @family_member.save
        redirect_to admin_family_members_path, notice: "#{@family_member.name} was added to the kitchen roster."
      else
        @family_members = current_household.family_members.order(:created_at)
        @new_member = @family_member
        render :index, status: :unprocessable_entity
      end
    end

    def edit
    end

    def update
      if @family_member.update(family_member_params)
        redirect_to admin_family_members_path, notice: "#{@family_member.name}'s profile was updated."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    def reset_pin
      new_pin = params[:pin].to_s.strip

      if !@family_member.admin?
        redirect_to admin_family_members_path, alert: "Non-admin members do not have a PIN."
        return
      end

      if !new_pin.match?(/\A\d{4}\z/)
        redirect_to admin_family_members_path, alert: "A valid 4-digit PIN is required for admin profiles."
        return
      end

      @family_member.pin = new_pin
      if @family_member.save
        redirect_to admin_family_members_path, notice: "4-Digit PIN for #{@family_member.name} has been updated."
      else
        redirect_to admin_family_members_path, alert: @family_member.errors.full_messages.to_sentence
      end
    end

    def destroy
      if current_household.family_members.count <= 1
        redirect_to admin_family_members_path, alert: "Your household must have at least one family member."
        return
      end

      if @family_member.admin? && current_household.family_members.where(role: "admin").count <= 1
        redirect_to admin_family_members_path, alert: "Your household must have at least one organizer/admin."
        return
      end

      name = @family_member.name
      was_active = (cookies.signed[:active_family_member_id] == @family_member.id)
      @family_member.destroy

      if was_active
        next_member = current_household.family_members.first
        cookies.signed[:active_family_member_id] = next_member&.id
        Current.family_member = next_member
      end

      redirect_to admin_family_members_path, notice: "#{name} was removed from the family kitchen."
    end

    private

    def set_family_member
      @family_member = current_household.family_members.find(params[:id])
    end

    def family_member_params
      allowed = params.require(:family_member).permit(:name, :avatar_color, :avatar_icon, :pin)
      allowed[:role] = params[:family_member][:role] if params.dig(:family_member, :role).in?(%w[admin member])
      allowed
    end
  end
end
