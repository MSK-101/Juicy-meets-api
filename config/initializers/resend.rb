# Resend configuration
if Rails.env.production?
  require 'resend'
  
  # Configure Resend API key
  Resend.api_key = ENV['RESEND_API_KEY']
end
