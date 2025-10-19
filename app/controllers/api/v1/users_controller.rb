class Api::V1::UsersController < ApplicationController
  skip_before_action :authenticate_user!, only: [:create, :validate_token]

  # POST /api/v1/users
  def create
    # Check if email is banned (prevent banned users from creating new accounts)
    if User.email_banned?(user_params[:email])
      render json: {
        success: false,
        message: "This email is associated with a banned account. Please contact support.",
        errors: ["Email is banned"]
      }, status: :forbidden
      return
    end

    # Check if user already exists with this email
    existing_user = User.find_by(email: user_params[:email])
    if existing_user.present?
      # Check if existing user is banned
      if existing_user.user_status == 'suspended'
        render json: {
          success: false,
          message: "This account has been suspended. Please contact support.",
          errors: ["Account suspended"]
        }, status: :forbidden
        return
      end

      # User already exists and is not banned, log them in automatically
      sign_in(existing_user)
      existing_user.update(last_activity_at: Time.current)

      # Get the JWT token from the request headers after sign_in
      token = request.env['warden-jwt_auth.token']

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
      sign_in(user)
      user.update(last_activity_at: Time.current)

      # Get the JWT token from the request headers after sign_in
      token = request.env['warden-jwt_auth.token']

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
    email = params[:email]

    if token.blank?
      render json: { valid: false, message: 'No token provided' }, status: :unauthorized
      return
    end

    # Use Devise JWT to validate the token
    begin
      # Set the token in the request headers for Devise to process
      request.headers['Authorization'] = "Bearer #{token}"

      # Try to authenticate the user with the token
      user = warden.authenticate(scope: :user)

      if user
        render json: {
          valid: true,
          user: user_response(user),
          message: 'Token is valid'
        }
      else
        # Token is invalid, but if email is provided, try to auto-login
        if email.present?
          user = User.find_by(email: email)
          if user
            # Auto-login the user and generate new token
            sign_in(user)
            user.update(last_activity_at: Time.current)
            new_token = request.env['warden-jwt_auth.token']

            render json: {
              valid: true,
              user: user_response(user),
              token: new_token,
              message: 'Token was invalid but user auto-logged in successfully'
            }
          else
            render json: {
              valid: false,
              message: 'Invalid token and user not found'
            }, status: :unauthorized
          end
        else
          render json: {
            valid: false,
            message: 'Invalid token'
          }, status: :unauthorized
        end
      end
    rescue => e
      # If token validation fails and email is provided, try auto-login
      if email.present?
        user = User.find_by(email: email)
        if user
          # Auto-login the user and generate new token
          sign_in(user)
          user.update(last_activity_at: Time.current)
          new_token = request.env['warden-jwt_auth.token']

          render json: {
            valid: true,
            user: user_response(user),
            token: new_token,
            message: 'Token was invalid but user auto-logged in successfully'
          }
        else
          render json: {
            valid: false,
            message: 'Invalid or expired token and user not found',
            error: e.message
          }, status: :unauthorized
        end
      else
        render json: {
          valid: false,
          message: 'Invalid or expired token',
          error: e.message
        }, status: :unauthorized
      end
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

  def warden
    request.env['warden']
  end
end
