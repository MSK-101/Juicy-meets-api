module AdminAuthenticatable
  extend ActiveSupport::Concern

  # Removed automatic before_action - controllers should add it manually where needed

  private

  def authenticate_admin!
    # If admin is already authenticated, return early
    return if @current_admin

    token = extract_token_from_header
    Rails.logger.info "Admin auth: Token extracted: #{token ? 'present' : 'missing'}"
    Rails.logger.info "Admin auth: Authorization header: #{request.headers['Authorization']}"

    # Try to authenticate with token first
    if token
      begin
        decoded_token = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })
        admin_data = decoded_token.first
        Rails.logger.info "Admin auth: Decoded token data: #{admin_data}"

        @current_admin = Admin.find(admin_data['admin_id'])
        Rails.logger.info "Admin auth: Admin found: #{@current_admin.email}"
        return
      rescue JWT::DecodeError => e
        Rails.logger.error "Admin auth: JWT decode error: #{e.message}"
        # Token is invalid, try auto-login with email
      rescue ActiveRecord::RecordNotFound => e
        Rails.logger.error "Admin auth: Admin not found: #{e.message}"
        # Admin not found, try auto-login with email
      end
    end

    # Try auto-login if email is provided in params
    if params[:email].present?
      admin = Admin.find_by(email: params[:email])
      if admin
        @current_admin = admin
        Rails.logger.info "🔄 Auto-logged in admin via email: #{admin.email}"
        return
      else
        Rails.logger.warn "⚠️ Email provided but admin not found: #{params[:email]}"
      end
    else
      Rails.logger.warn "⚠️ No email parameter provided for admin auto-login"
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
