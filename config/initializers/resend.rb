# Resend configuration
if Rails.env.production?
  require 'resend'

  # Configure Resend API key
  Resend.api_key = ENV['RESEND_API_KEY']

  # Add error handling for better debugging
  Rails.logger.info "Resend configured with API key: #{ENV['RESEND_API_KEY'].present? ? 'Present' : 'Missing'}"
end
