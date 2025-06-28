class Api::V1::UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create]

  # GET /api/v1/users/profile
  def profile
    render json: current_user
  end

  # POST /api/v1/users
  def create
    user = User.new(user_params)

    if user.save
      render json: user, status: :created
    else
      render json: { errors: user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end
end
