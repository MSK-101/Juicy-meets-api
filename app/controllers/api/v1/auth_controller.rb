class Api::V1::AuthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:oauth_urls, :providers, :simulate_oauth]

  # GET /api/v1/auth/oauth_urls
  def oauth_urls
    base_url = "#{request.protocol}#{request.host_with_port}"

    render json: {
      success: true,
      message: 'OAuth URLs',
      data: {
        google: {
          url: "#{base_url}/auth/google_oauth2",
          callback_url: "#{base_url}/auth/google_oauth2/callback"
        }
      }
    }
  end

  # GET /api/v1/auth/providers
  def providers
    render json: {
      success: true,
      message: 'Available authentication providers',
      data: {
        providers: [
          {
            name: 'google',
            display_name: 'Google',
            icon: 'google',
            auth_url: "#{request.protocol}#{request.host_with_port}/auth/google_oauth2"
          },
          {
            name: 'email',
            display_name: 'Email',
            icon: 'email',
            signup_url: "#{request.protocol}#{request.host_with_port}/api/v1/users",
            login_url: "#{request.protocol}#{request.host_with_port}/api/v1/login"
          }
        ]
      }
    }
  end

  # POST /api/v1/auth/simulate_oauth
  def simulate_oauth
    # This simulates what happens when Google OAuth returns user data
    email = params[:email] || 'test@gmail.com'

    # Create OAuth auth hash similar to what Google would provide
    # Generate unique UID based on email to avoid collisions
    uid = Digest::MD5.hexdigest(email)[0..10]

    auth_hash = {
      'provider' => 'google_oauth2',
      'uid' => uid,
      'info' => {
        'email' => email,
        'name' => 'Test User'
      }
    }

    # Convert to OpenStruct-like object
    auth_hash = Struct.new(:provider, :uid, :info).new(
      auth_hash['provider'],
      auth_hash['uid'],
      Struct.new(:email, :name).new(auth_hash['info']['email'], auth_hash['info']['name'])
    )

    begin
      user = User.from_omniauth(auth_hash)

      if user.persisted?
        # Generate JWT token for the user
        warden.set_user(user, store: false)
        token = request.env['warden-jwt_auth.token']

        render json: {
          success: true,
          message: 'OAuth simulation successful',
          user: {
            id: user.id,
            email: user.email,
            provider: user.provider,
            confirmed: user.confirmed?,
            oauth_user: user.oauth_user?,
            age: user.age,
            gender: user.gender,
            interested_in: user.interested_in,
            profile_completed: user.profile_completed,
            created_at: user.created_at
          },
          token: token
        }, status: :ok
      else
        render json: {
          success: false,
          message: 'OAuth simulation failed',
          errors: user.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue => e
      render json: {
        success: false,
        message: 'OAuth simulation error',
        error: e.message
      }, status: :internal_server_error
    end
  end
end
