class Api::V1::PasswordRecoveryController < ApplicationController
  skip_before_action :authenticate_user!, only: [:forgot_password]

  # POST /api/v1/password-recovery/forgot
  def forgot_password
    user = User.find_by(email: params[:email])

    if user.nil?
      # For security, don't reveal if email exists or not
      render json: {
        success: true,
        message: 'If the email exists in our system, you will receive a new password shortly.'
      }, status: :ok
      return
    end

    # Generate new password and send email
    user.send_forgot_password_email

    render json: {
      success: true,
      message: 'New password has been sent to your email address.'
    }, status: :ok
  end
end
