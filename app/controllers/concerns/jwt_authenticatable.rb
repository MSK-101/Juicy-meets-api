module JwtAuthenticatable
  extend ActiveSupport::Concern

  included do
    before_action :authenticate_user_from_jwt!
  end

  private

  def authenticate_user_from_jwt!
    token = extract_token_from_header

    if token.blank?
      render_unauthorized('No authentication token provided')
      return
    end

    begin
      decoded_token = decode_jwt_token(token)
      @current_user = User.find(decoded_token['user_id'])

      unless @current_user
        render_unauthorized('Invalid user')
        return
      end
    rescue JWT::DecodeError => e
      render_unauthorized('Invalid authentication token')
      return
    rescue ActiveRecord::RecordNotFound => e
      render_unauthorized('User not found')
      return
    end
  end

  def current_user
    @current_user
  end

  def extract_token_from_header
    auth_header = request.headers['Authorization']
    return nil unless auth_header

    # Extract token from "Bearer <token>" format
    token = auth_header.split(' ').last
    token.presence
  end

  def decode_jwt_token(token)
    decoded = JWT.decode(token, Rails.application.secret_key_base, true, { algorithm: 'HS256' })
    decoded.first
  end

  def render_unauthorized(message)
    render json: {
      success: false,
      message: message,
      errors: ['Authentication required']
    }, status: :unauthorized
  end
end
