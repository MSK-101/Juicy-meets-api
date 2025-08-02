module AdminAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_admin!
  end

  private

  def authenticate_admin!
    token = extract_token_from_header
    return render_unauthorized unless token

    begin
      decoded_token = JWT.decode(token, Rails.application.credentials.secret_key_base, true, { algorithm: 'HS256' })
      admin_data = decoded_token.first

      @current_admin = Admin.find(admin_data['admin_id'])
    rescue JWT::DecodeError, ActiveRecord::RecordNotFound
      render_unauthorized
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

  def render_unauthorized
    render json: {
      success: false,
      message: 'Unauthorized access',
      errors: ['Invalid or missing authentication token']
    }, status: :unauthorized
  end
end
