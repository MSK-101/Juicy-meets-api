module AdminAuthenticatable
  extend ActiveSupport::Concern

  # Removed automatic before_action - controllers should add it manually where needed

  private

  def authenticate_admin!
    # If admin is already authenticated, return early
    return if @current_admin

    token = extract_token_from_header

    # Try to authenticate with token first
    if token
      begin
        decoded_token = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })
        admin_data = decoded_token.first

        @current_admin = Admin.find(admin_data['admin_id'])
        return
      rescue JWT::DecodeError => e
        # Token is invalid, try auto-login with email
      rescue ActiveRecord::RecordNotFound => e
        # Admin not found, try auto-login with email
      end
    end

    # Try auto-login if email is provided in params (regardless of token validity)
    if params[:email].present?
      admin = Admin.find_by(email: params[:email])
      if admin
        @current_admin = admin

        # Generate new token without expiration for auto-login
        new_token = JWT.encode(
          {
            admin_id: admin.id,
            email: admin.email,
            role: admin.role
          },
          Rails.application.secret_key_base
        )

        # Add new token to response headers
        response.headers['X-New-Token'] = new_token
        return
      end
    end

    # If no admin found and no auto-login possible, return unauthorized
    render_admin_unauthorized
  end

  def current_admin
    @current_admin
  end

  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return nil unless auth_header

    auth_header.split(' ').last
  end

  def render_admin_unauthorized
    render json: {
      success: false,
      message: 'Unauthorized access',
      errors: ['Invalid or missing authentication token']
    }, status: :unauthorized
  end
end
