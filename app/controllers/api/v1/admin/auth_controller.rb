class Api::V1::Admin::AuthController < ApplicationController
  include AdminAuthenticatable
  skip_before_action :authenticate_user!, only: [:login, :logout]
  skip_before_action :authenticate_admin!, only: [:login, :logout]

  # POST /api/v1/admin/auth/login
  def login
    admin = Admin.find_by(email: params[:email])

    if admin&.authenticate(params[:password])
      # Generate JWT token for admin
      token = JWT.encode(
        {
          admin_id: admin.id,
          email: admin.email,
          role: admin.role,
          exp: 24.hours.from_now.to_i
        },
        Rails.application.credentials.secret_key_base
      )

      render json: {
        success: true,
        message: 'Admin login successful',
        data: {
          admin: admin_response(admin),
          token: token
        }
      }
    else
      render json: {
        success: false,
        message: 'Invalid email or password',
        errors: ['Invalid credentials']
      }, status: :unauthorized
    end
  end

  # DELETE /api/v1/admin/auth/logout
  def logout
    # In a real app, you might want to blacklist the token
    render json: {
      success: true,
      message: 'Admin logout successful'
    }
  end

  # GET /api/v1/admin/auth/me
  def me
    render json: {
      success: true,
      data: {
        admin: admin_response(current_admin)
      }
    }
  end

  private

  def admin_response(admin)
    {
      id: admin.id,
      email: admin.email,
      role: admin.role,
      display_name: admin.display_name,
      created_at: admin.created_at,
      updated_at: admin.updated_at
    }
  end
end
