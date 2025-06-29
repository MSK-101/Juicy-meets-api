class Api::V1::SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create]

    # POST /api/v1/login
  def create
    user = User.find_by(email: session_params[:email])

    if user && user.valid_password?(session_params[:password])
      # Check if user's email is confirmed
      unless user.confirmed?
        render json: {
          success: false,
          message: 'Please confirm your email address before signing in',
          confirmation_required: true,
          user: {
            id: user.id,
            email: user.email,
            confirmed: false
          }
        }, status: :unauthorized
        return
      end

      # Use warden directly to avoid session issues
      warden.set_user(user, store: false)
      token = request.env['warden-jwt_auth.token']

      render json: {
        success: true,
        user: {
          id: user.id,
          email: user.email,
          confirmed: user.confirmed?,
          created_at: user.created_at,
          profile_completed: user.profile_completed
        },
        token: token,
        message: 'Successfully signed in'
      }
    else
      render json: {
        success: false,
        errors: ['Invalid email or password']
      }, status: :unauthorized
    end
  end

  # DELETE /api/v1/logout
  def destroy
    if current_user
      warden.logout
      render json: { message: 'Successfully signed out' }
    else
      render json: { error: 'No user signed in' }, status: :unauthorized
    end
  end

  private

  def session_params
    params.require(:user).permit(:email, :password)
  end

  def warden
    request.env['warden']
  end
end
