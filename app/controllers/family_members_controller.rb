class FamilyMembersController < ApplicationController
  before_action :set_family_member, only: %i[update destroy switch]

  def index
    @family_members = current_household.family_members.order(:created_at)
    @new_member = current_household.family_members.build
  end

  def create
    @family_member = current_household.family_members.build(family_member_params)
    if @family_member.save
      redirect_to family_members_path, notice: "#{@family_member.name} joined the family kitchen!"
    else
      @family_members = current_household.family_members.order(:created_at)
      render :index, status: :unprocessable_entity
    end
  end

  def update
    if @family_member.update(family_member_params)
      redirect_to family_members_path, notice: "#{@family_member.name}'s profile updated."
    else
      @family_members = current_household.family_members.order(:created_at)
      render :index, status: :unprocessable_entity
    end
  end

  def destroy
    if current_household.family_members.count <= 1
      redirect_to family_members_path, alert: "Your household must have at least one family member."
      return
    end

    name = @family_member.name
    was_active = (cookies.signed[:active_family_member_id] == @family_member.id)
    @family_member.destroy

    if was_active
      next_member = current_household.family_members.first
      cookies.signed[:active_family_member_id] = next_member&.id
    end

    redirect_to family_members_path, notice: "#{name} was removed."
  end

  def switch
    if @family_member.requires_pin? && !@family_member.verify_pin(params[:pin])
      redirect_back fallback_location: root_path, alert: "Incorrect PIN for #{@family_member.name}."
      return
    end

    cookies.signed.permanent[:active_family_member_id] = @family_member.id
    Current.family_member = @family_member

    redirect_back fallback_location: root_path, notice: "Now browsing as #{@family_member.name}"
  end

  private

  def set_family_member
    @family_member = current_household.family_members.find(params[:id])
  end

  def family_member_params
    params.require(:family_member).permit(:name, :avatar_color, :avatar_icon, :role, :pin)
  end
end
