class Api::V1::UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create]

  # GET /api/v1/users/profile
  def profile
    render json: {
      user: user_response(current_user)
    }
  end

  # POST /api/v1/users
  def create
    user = User.new(user_params)

    if user.save
      # Send confirmation email
      user.send_confirmation_instructions

      render json: {
        success: true,
        user: {
          id: user.id,
          email: user.email,
          confirmed: user.confirmed?,
          confirmation_sent: true,
          created_at: user.created_at
        },
        message: 'User successfully created. Please check your email for confirmation instructions.'
      }, status: :created
    else
      render json: {
        success: false,
        errors: user.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # PUT /api/v1/users/complete_profile
  def complete_profile
    if current_user.update(profile_params)
      current_user.complete_profile!
      render json: {
        user: user_response(current_user),
        message: 'Profile completed successfully'
      }
    else
      render json: { errors: current_user.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :password, :password_confirmation)
  end

  def profile_params
    params.require(:user).permit(:age, :gender, :interested_in)
  end

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
