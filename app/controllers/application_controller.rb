class ApplicationController < ActionController::API
  include ActionController::MimeResponds
  include ActionController::Cookies
  include Devise::Controllers::Helpers
  before_action :set_session_store
  before_action :authenticate_user!
  respond_to :json
  private

  def authenticate_user!
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
