# frozen_string_literal: true

# Where a signed-in person accepts the current hosted Terms of Service: before
# first using a household if they never have (a Google sign-in, say), and
# when a changed version is announced or has come into force for them.
# Reachable whatever the Terms gate, billing or suspension say, so it can
# never redirect to itself.
class TermsAcceptancesController < ApplicationController
  allow_unauthenticated_access
  skip_before_action :handle_suspended_household
  allow_without_current_terms

  KIOSK_NOTICE = TermsAssent::KIOSK_ALERT

  before_action :require_hosted
  before_action :require_user

  def show
    redirect_to after_acceptance_path if TermsAssent.current?(current_user)
  end

  def create
    if TermsAssent.current?(current_user)
      redirect_to after_acceptance_path and return
    end

    # Includes refusing a kitchen display (HostedAccess).
    if (problem = terms_assent_problem)
      flash.now[:alert] = problem
      render :show, status: terms_assent_problem_status(problem) and return
    end

    context = TermsAssent.pending_change?(current_user) ? "reacceptance" : "first_use"
    record_terms_assent!(context: context, household: current_household)
    redirect_to after_acceptance_path, notice: "Thank you. You have accepted the Terms of Service."
  end

  private

  def require_hosted
    redirect_to root_path unless FamilyPlates.config.hosted?
  end

  def require_user
    redirect_to new_session_path, alert: "Please sign in to continue." if current_user.nil?
  end

  # Only ever a path this app stored for a GET it turned away.
  def after_acceptance_path
    path = session.delete(:return_to_after_terms).to_s
    path.start_with?("/") && !path.start_with?("//") ? path : root_path
  end
end
