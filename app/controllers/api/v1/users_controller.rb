class Api::V1::UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create]

  # POST /api/v1/users
  def create
    user = User.new(user_params)

    if user.save
      # Send confirmation email (only for non-OAuth users)
      user.send_confirmation_instructions unless user.oauth_user?

      render json: {
        success: true,
        data: {
          user: user_response(user)
        },
        message: user.oauth_user? ?
          'User successfully created with OAuth.' :
          'User successfully created. Please check your email for confirmation instructions.'
      }, status: :created
    else
      render json: {
        success: false,
        errors: user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # GET /api/v1/users/me
  def show
    render json: {
      success: true,
      data: {
        user: user_response(current_user)
      }
    }
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
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
