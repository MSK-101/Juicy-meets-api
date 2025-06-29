class Api::V1::AuthController < ApplicationController
  skip_before_action :authenticate_user!, only: [:providers, :oauth_urls]

  # GET /api/v1/auth/providers
  def providers
    render json: {
      success: true,
      message: 'Available authentication providers',
      data: {
        providers: available_providers
      }
    }
  end

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

  private

    def available_providers
    base_url = "#{request.protocol}#{request.host_with_port}"

    providers = [
      {
        name: 'google',
        display_name: 'Google',
        icon: 'google',
        type: 'oauth',
        auth_url: "#{base_url}/auth/google_oauth2"
      },
      {
        name: 'email',
        display_name: 'Email',
        icon: 'email',
        type: 'credentials',
        signup_url: "#{base_url}/api/v1/users",
        login_url: "#{base_url}/api/v1/login"
      }
    ]

    # Add testing information in development
    if Rails.env.development?
      providers << {
        name: 'google_test',
        display_name: 'Google (Test Mode)',
        icon: 'google',
        type: 'oauth_test',
        test_url: "#{base_url}/auth/google_oauth2/callback",
        method: 'POST',
        params: { test_email: 'user@example.com' },
        description: 'Tests the real OAuth controller with mock data (development only)'
      }
    end

    providers
  end
end
