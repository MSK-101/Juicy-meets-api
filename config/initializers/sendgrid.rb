# SendGrid configuration
if Rails.env.production?
  require 'sendgrid-ruby'
  include SendGrid

  # Set up error handling for SendGrid SMTP
  if Rails.application.config.action_mailer.smtp_settings.present?
    Rails.application.config.action_mailer.smtp_settings.merge!(
      return_response: true,
      open_timeout: 10,
      read_timeout: 10
    )
  end
end
