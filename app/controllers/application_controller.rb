class ApplicationController < ActionController::API
  include ActionController::MimeResponds
  include ActionController::Cookies
  include Devise::Controllers::Helpers
  before_action :set_session_store
  before_action :authenticate_user!
  respond_to :json
  private

  def authenticate_user!
    # If user is already authenticated, return early
    return if current_user

    # Try auto-login if email is provided in params
    if params[:email].present?
      user = User.find_by(email: params[:email])
      if user
        sign_in(user)
        Rails.logger.info "🔄 Auto-logged in user via email: #{user.email}"

        # Get the new token from Devise JWT
        new_token = request.env['warden-jwt_auth.token']
        if new_token
          response.headers['X-New-Token'] = new_token
        end

        return
      else
        Rails.logger.warn "⚠️ Email provided but user not found: #{params[:email]}"
      end
    else
      Rails.logger.warn "⚠️ No email parameter provided for auto-login"
    end

    # If no current user and no auto-login possible, return unauthorized
    unless current_user
      render json: {
        success: false,
        message: 'Authentication required',
        errors: ['Please log in to continue']
      }, status: :unauthorized
    end
  end

  def set_session_store
    request.session_options[:skip] = false
  end
end
