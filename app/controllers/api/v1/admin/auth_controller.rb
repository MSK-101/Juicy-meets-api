class Api::V1::Admin::AuthController < Api::V1::Admin::BaseController
  # Only include AdminAuthenticatable for actions that need admin authentication
  before_action :authenticate_admin!, only: [:me, :change_password]
  include AdminAuthenticatable

  # POST /api/v1/admin/auth/login
  def login
    admin = Admin.find_by(email: params[:email])

    if admin&.authenticate(params[:password])
      # Generate JWT token for admin (no expiration)
      token = JWT.encode(
        {
          admin_id: admin.id,
          email: admin.email,
          role: admin.role
          # No 'exp' field = token never expires
        },
        Rails.application.secret_key_base
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

  # PUT /api/v1/admin/auth/change_password
  def change_password
    if current_admin.authenticate(params[:old_password])
      # Update password without triggering role validation
      current_admin.password = params[:new_password]
      current_admin.password_confirmation = params[:new_password]

      if current_admin.save(validate: false)
        render json: {
          success: true,
          message: 'Password updated successfully'
        }
      else
        render json: {
          success: false,
          message: 'Failed to update password',
          errors: current_admin.errors.full_messages
        }, status: :unprocessable_entity
      end
    else
      render json: {
        success: false,
        message: 'Current password is incorrect'
      }, status: :unauthorized
    end
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
