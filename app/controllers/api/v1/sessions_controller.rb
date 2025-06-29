class Api::V1::SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create]

    # POST /api/v1/login
  def create
    user = User.find_by(email: session_params[:email])

    if user && user.valid_password?(session_params[:password])
      # Check if user's email is confirmed (except for OAuth users)
      unless user.confirmed? || user.oauth_user?
        render json: {
          success: false,
          message: 'Please confirm your email address before signing in',
          data: {
            confirmation_required: true,
            user: {
              id: user.id,
              email: user.email,
              confirmed: false,
              oauth_user: user.oauth_user?
            }
          }
        }, status: :unauthorized
        return
      end

      # Use warden directly to avoid session issues
      warden.set_user(user, store: false)
      token = request.env['warden-jwt_auth.token']

      render json: {
        success: true,
        message: 'Successfully signed in',
        data: {
          user: user_response(user),
          token: token
        }
      }
    else
      render json: {
        success: false,
        message: 'Invalid email or password',
        errors: ['Invalid email or password']
      }, status: :unauthorized
    end
  end

  # DELETE /api/v1/logout
  def destroy
    if current_user
      warden.logout
      render json: {
        success: true,
        message: 'Successfully signed out'
      }
    else
      render json: {
        success: false,
        message: 'No user signed in',
        errors: ['No active session found']
      }, status: :unauthorized
    end
  end

  private

  def session_params
    params.require(:user).permit(:email, :password)
  end

  def warden
    request.env['warden']
  end

  def user_response(user)
    {
      id: user.id,
      email: user.email,
      provider: user.provider,
      oauth_user: user.oauth_user?,
      confirmed: user.confirmed?,
      confirmed_at: user.confirmed_at,
      profile_completed: user.profile_completed?,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end
end
