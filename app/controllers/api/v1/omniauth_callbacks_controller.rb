class Api::V1::OmniauthCallbacksController < ApplicationController
  skip_before_action :authenticate_user!, only: [:google_oauth2, :failure]

  # GET /auth/google_oauth2/callback
  # POST /auth/google_oauth2/callback (for testing in development)
  def google_oauth2
    begin
      # Get auth data from either real OAuth flow or development test data
      auth_data = get_auth_data

      unless auth_data
        render json: {
          success: false,
          message: 'No authentication data provided'
        }, status: :bad_request
        return
      end

      user = User.from_omniauth(auth_data)

      if user.persisted?
        # Generate JWT token for the user
        warden.set_user(user, store: false)
        token = request.env['warden-jwt_auth.token']

        render json: {
          success: true,
          message: 'Successfully authenticated with Google',
          data: {
            user: user_response(user),
            token: token,
            auth_method: Rails.env.development? && params[:test_email] ? 'test' : 'oauth'
          }
        }, status: :ok
      else
        render json: {
          success: false,
          message: 'Authentication failed',
          errors: user.errors.full_messages
        }, status: :unprocessable_entity
      end
    rescue => e
      Rails.logger.error "OAuth Error: #{e.message}"
      render json: {
        success: false,
        message: 'Authentication failed',
        error: e.message
      }, status: :internal_server_error
    end
  end

  # GET /auth/failure
  def failure
    error_msg = params[:message] || 'Authentication failed'
    render json: {
      success: false,
      message: 'OAuth authentication failed',
      error: error_msg
    }, status: :unauthorized
  end

  private

  def get_auth_data
    # In production, always use real OAuth data
    return request.env["omniauth.auth"] unless Rails.env.development?

    # In development, allow test data via POST parameters (for testing only)
    if request.post? && params[:test_email].present?
      create_test_auth_data(params[:test_email])
    else
      # Normal OAuth flow in development
      request.env["omniauth.auth"]
    end
  end

  def create_test_auth_data(email)
    # Generate unique UID for testing
    uid = Digest::MD5.hexdigest(email + Time.current.to_s)[0..10]

    # Create auth hash similar to what Google OAuth provides
    Struct.new(:provider, :uid, :info).new(
      'google_oauth2',
      uid,
      Struct.new(:email, :name).new(email, 'Test User')
    )
  end

  def user_response(user)
    {
      id: user.id,
      email: user.email,
      provider: user.provider,
      confirmed: user.confirmed?,
      confirmed_at: user.confirmed_at,
      oauth_user: false,
      age: user.age,
      gender: user.gender,
      interested_in: user.interested_in,
      profile_completed: user.profile_completed?,
      created_at: user.created_at,
      updated_at: user.updated_at
    }
  end
end
