class Api::V1::UsersController < ApplicationController
  skip_before_action :authenticate_user_from_jwt!, only: [:create, :validate_token]

  # POST /api/v1/users
  def create
    # Check if user already exists with this email
    existing_user = User.find_by(email: user_params[:email])

    if existing_user.present?
      # User already exists, log them in automatically
      token = generate_jwt_token(existing_user)

      render json: {
        success: true,
        data: {
          user: user_response(existing_user),
          token: token,
          free_coins: { success: false, coins_given: 0, message: "User already exists" }
        },
        message: "User already exists. Logged in automatically.",
        user_exists: true
      }, status: :ok
      return
    end

    # Create new user
    user = User.new(user_params)

    # Set default status to pending
    user.user_status = :pending

    # Automatically confirm users (email confirmation disabled)
    # Generate random password for the user
    user.password = SecureRandom.hex(16)

    if user.save
      # Process free coins and IP tracking
      ip_result = user.give_free_coins_and_track_ip!(request.remote_ip)

      # Generate JWT token for the new user
      token = generate_jwt_token(user)

      render json: {
        success: true,
        data: {
          user: user_response(user),
          token: token,
          free_coins: ip_result
        },
        message: "User created successfully and logged in automatically.",
        user_exists: false
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

  # POST /api/v1/users/validate_token
  def validate_token
    # This endpoint validates if a JWT token is still valid
    # It's called without authentication to check token validity
    token = request.headers['Authorization']&.split(' ')&.last

    if token.blank?
      render json: { valid: false, message: 'No token provided' }, status: :unauthorized
      return
    end

    begin
      decoded_token = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })
      user_id = decoded_token.first['user_id']
      user = User.find(user_id)

      render json: {
        valid: true,
        user: user_response(user),
        message: 'Token is valid'
      }
    rescue JWT::DecodeError, JWT::ExpiredSignature, ActiveRecord::RecordNotFound => e
      render json: {
        valid: false,
        message: 'Invalid or expired token',
        error: e.message
      }, status: :unauthorized
    end
  end

  private

  def user_params
    params.require(:user).permit(:email, :age, :gender, :interested_in)
  end

  def user_response(user)
    {
      id: user.id,
      email: user.email,
      age: user.age,
      gender: user.gender,
      interested_in: user.interested_in,
      provider: user.provider,
      oauth_user: false,
      confirmed: true, # Always true since confirmation is disabled
      confirmed_at: user.confirmed_at,
      profile_completed: user.profile_completed?,
      role: user.role,
      user_status: user.user_status,
      coin_balance: user.coin_balance,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end

  def generate_jwt_token(user)
    payload = {
      user_id: user.id,
      email: user.email,
      exp: 24.hours.from_now.to_i,
      iat: Time.current.to_i
    }

    JWT.encode(payload, Rails.application.secret_key_base, 'HS256')
  end

  def warden
    request.env['warden']
  end
end
