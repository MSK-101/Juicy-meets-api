class DeviseMailer < Devise::Mailer
  include Devise::Controllers::UrlHelpers

    def confirmation_instructions(record, token, opts = {})
    @token = token
    @resource = record
    @confirmation_url = "#{Rails.application.config.action_mailer.default_url_options[:host]}/confirm?token=#{@token}"

    mail(
      to: @resource.email,
      subject: 'Confirmation instructions',
      template_path: 'devise/mailer',
      template_name: 'confirmation_instructions'
    )
  end
end
