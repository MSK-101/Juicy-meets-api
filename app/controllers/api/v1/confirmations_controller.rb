class Api::V1::ConfirmationsController < ApplicationController
  before_action :authenticate_user!, only: [:resend]

  # POST /api/v1/confirmation/confirm
  def confirm
    token = params[:confirmation_token] || params[:token]
    user = User.find_by(confirmation_token: token)

    if user.nil?
      render json: {
        success: false,
        message: 'Invalid confirmation token'
      }, status: :not_found
      return
    end

    if user.confirmed?
      render json: {
        success: false,
        message: 'Email already confirmed'
      }, status: :unprocessable_entity
      return
    end

    if user.confirm
      render json: {
        success: true,
        message: 'Email confirmed successfully',
        data: {
          user: {
            id: user.id,
            email: user.email,
            confirmed: true,
            confirmed_at: user.confirmed_at
          }
        }
      }, status: :ok
    else
      render json: {
        success: false,
        message: 'Failed to confirm email',
        errors: user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # POST /api/v1/confirmation/resend
  def resend
    if current_user.confirmed?
      render json: {
        success: false,
        message: 'Email is already confirmed'
      }, status: :unprocessable_entity
      return
    end

    current_user.send_confirmation_instructions

    render json: {
      success: true,
      message: 'Confirmation instructions sent to your email address'
    }, status: :ok
  end

  # POST /api/v1/confirmation/send_email
  def send_email
    user = User.find_by(email: params[:email])

    if user.nil?
      render json: {
        success: false,
        message: 'User not found with this email address'
      }, status: :not_found
      return
    end

    if user.confirmed?
      render json: {
        success: false,
        message: 'Email is already confirmed'
      }, status: :unprocessable_entity
      return
    end

    user.send_confirmation_instructions

    render json: {
      success: true,
      message: 'Confirmation instructions sent to your email address'
    }, status: :ok
  end
end
