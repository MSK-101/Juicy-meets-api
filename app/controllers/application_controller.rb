class ApplicationController < ActionController::API
  include ActionController::MimeResponds
  include ActionController::Cookies
  include Devise::Controllers::Helpers
  include JwtAuthenticatable

  before_action :set_session_store
  # before_action :authenticate_user! # Commented out - using JWT authentication instead

  respond_to :json

  # JWT authentication is now handled by the JwtAuthenticatable concern
  # The authenticate_user! method is no longer needed here

  private

  def set_session_store
    request.session_options[:skip] = false
  end
end
