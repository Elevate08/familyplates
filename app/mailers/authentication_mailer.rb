class AuthenticationMailer < ApplicationMailer
  default from: "noreply@familyplates.app"

  def magic_code(magic_code)
    @code = magic_code.code
    @email = magic_code.email

    mail to: @email, subject: "Your FamilyPlates sign-in code"
  end

  def verification_code(magic_code)
    @code = magic_code.code
    @email = magic_code.email

    mail to: @email, subject: "Verify your email for FamilyPlates"
  end
end
