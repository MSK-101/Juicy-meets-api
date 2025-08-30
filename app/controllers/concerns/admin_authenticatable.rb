module AdminAuthenticatable
  extend ActiveSupport::Concern

  # Removed automatic before_action - controllers should add it manually where needed

  private

  def authenticate_admin!
    token = extract_token_from_header
    Rails.logger.info "Admin auth: Token extracted: #{token ? 'present' : 'missing'}"
    Rails.logger.info "Admin auth: Authorization header: #{request.headers['Authorization']}"
    return render_admin_unauthorized unless token

    begin
      decoded_token = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })
      admin_data = decoded_token.first
      Rails.logger.info "Admin auth: Decoded token data: #{admin_data}"

      @current_admin = Admin.find(admin_data['admin_id'])
      Rails.logger.info "Admin auth: Admin found: #{@current_admin.email}"
    rescue JWT::DecodeError => e
      Rails.logger.error "Admin auth: JWT decode error: #{e.message}"
      render_admin_unauthorized
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "Admin auth: Admin not found: #{e.message}"
      render_admin_unauthorized
    end
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
