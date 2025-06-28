class Api::V1::SessionsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create]

  # POST /api/v1/login
  def create
    user = User.find_by(email: session_params[:email])

    if user && user.valid_password?(session_params[:password])
      sign_in user
      render json: user
    else
      render json: { errors: ['Invalid email or password'] }, status: :unauthorized
    end
  end

  # DELETE /api/v1/logout
  def destroy
    sign_out current_user
    render json: { message: 'Successfully signed out' }
  end

  private

  def session_params
    params.require(:user).permit(:email, :password)
  end
end
