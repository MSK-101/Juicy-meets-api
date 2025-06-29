class Api::V1::OmniauthCallbacksController < ApplicationController
  skip_before_action :authenticate_user!, only: [:google_oauth2, :failure]

  # GET /auth/google_oauth2/callback
  def google_oauth2
    begin
      user = User.from_omniauth(request.env["omniauth.auth"])

      if user.persisted?
        # Generate JWT token for the user
        warden.set_user(user, store: false)
        token = request.env['warden-jwt_auth.token']

        render json: {
          success: true,
          message: 'Successfully authenticated with Google',
          user: user_response(user),
          token: token
        }, status: :ok
      else
        render json: {
          success: false,
          message: 'Authentication failed',
          errors: user.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "OAuth Error: #{e.message}"
      render json: {
        success: false,
        message: 'Authentication failed',
        error: e.message
      }, status: :internal_server_error
    end
  end

  # GET /auth/failure
  def failure
    error_msg = params[:message] || 'Authentication failed'
    render json: {
      success: false,
      message: 'OAuth authentication failed',
      error: error_msg
    }, status: :unauthorized
  end

  private

  def user_response(user)
    {
      id: user.id,
      email: user.email,
      provider: user.provider,
      confirmed: user.confirmed?,
      confirmed_at: user.confirmed_at,
      oauth_user: user.oauth_user?,
      age: user.age,
      gender: user.gender,
      interested_in: user.interested_in,
      profile_completed: user.profile_completed,
      created_at: user.created_at
    }
  end
end
