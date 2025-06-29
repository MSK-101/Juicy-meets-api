class Api::V1::SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create]

    # POST /api/v1/login
  def create
    user = User.find_by(email: session_params[:email])

    if user && user.valid_password?(session_params[:password])
      # Use warden directly to avoid session issues
      warden.set_user(user, store: false)
      token = request.env['warden-jwt_auth.token']

      render json: {
        user: {
          id: user.id,
          email: user.email,
          created_at: user.created_at
        },
        token: token,
        message: 'Successfully signed in'
      }
    else
      render json: { errors: ['Invalid email or password'] }, status: :unauthorized
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
