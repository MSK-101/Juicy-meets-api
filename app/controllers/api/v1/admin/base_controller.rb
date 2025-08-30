class Api::V1::Admin::BaseController < ActionController::API
  include ActionController::MimeResponds
  include ActionController::Cookies
  include Devise::Controllers::Helpers

  respond_to :json

  private

  def set_session_store
    request.session_options[:skip] = false
  end
end
