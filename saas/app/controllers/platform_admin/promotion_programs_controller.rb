module PlatformAdmin
  class PromotionProgramsController < BaseController
    def index
      @promotion_programs = PromotionProgram.order(created_at: :desc, id: :desc)
      @promotion_program = PromotionProgram.new
    end

    def create
      @promotion_program = PromotionProgram.new(promotion_program_params)
      if @promotion_program.save
        record_platform_audit!("promotion_program.created", target: @promotion_program, metadata: { code: @promotion_program.code })
        redirect_to platform_admin_promotion_programs_path, notice: "Promotion program created."
      else
        @promotion_programs = PromotionProgram.order(created_at: :desc, id: :desc)
        render :index, status: :unprocessable_entity
      end
    end

    def update
      @promotion_program = PromotionProgram.find(params[:id])
      if @promotion_program.update(promotion_program_params)
        record_platform_audit!("promotion_program.updated", target: @promotion_program)
        redirect_to platform_admin_promotion_programs_path, notice: "Promotion program updated."
      else
        redirect_to platform_admin_promotion_programs_path, alert: @promotion_program.errors.full_messages.to_sentence
      end
    end

    private

    def promotion_program_params
      params.require(:promotion_program).permit(:name, :code, :discount_percent, :provider_promotion_code_id, :starts_at, :ends_at, :max_redemptions, :notes, :active)
    end
  end
end
