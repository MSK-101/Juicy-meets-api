class UserMailer < ApplicationMailer

  # def password_email(user, password)
  #   @user = user
  #   @password = password

  #   mail(
  #     to: @user.email,
  #     subject: 'Welcome to Juicy Meets - Your Password'
  #   )
  # end

  def password_email(user, password)
    require 'resend'
    Resend.api_key = ENV['RESEND_API_KEY']
    @user = user
    @password = password

    # Render HTML version with layout
    html_content = render_to_string(
      template: 'user_mailer/password_email',
      layout: 'mailer',
      formats: [:html]
    )

    # Render text version with layout
    text_content = render_to_string(
      template: 'user_mailer/password_email',
      layout: 'mailer',
      formats: [:text]
    )

        # Send via Resend API
    begin
      result = Resend::Emails.send({
        "from": "Juicy Meets <onboarding@resend.dev>",
        "to": [user.email],
        "subject": "Welcome to Juicy Meets - Your Password",
        "html": html_content,
        "text": text_content
      })

      Rails.logger.info "Password email sent successfully: #{result[:id]}"
      result
    rescue Resend::Error => e
      Rails.logger.error "Resend Error Details:"
      Rails.logger.error "  Message: #{e.message}"
      Rails.logger.error "  Class: #{e.class}"
      Rails.logger.error "  Response: #{e.response_body if e.respond_to?(:response_body)}"
      Rails.logger.error "  Status: #{e.status_code if e.respond_to?(:status_code)}"
      Rails.logger.error "  Full error: #{e.inspect}"
      raise e
    end
  end

  def forgot_password_email(user, password)
    require 'resend'
    Resend.api_key = ENV['RESEND_API_KEY']
    @user = user
    @password = password

    # Render HTML version with layout
    html_content = render_to_string(
      template: 'user_mailer/forgot_password_email',
      layout: 'mailer',
      formats: [:html]
    )

    # Render text version with layout
    text_content = render_to_string(
      template: 'user_mailer/forgot_password_email',
      layout: 'mailer',
      formats: [:text]
    )

    # Send via Resend API
    result = Resend::Emails.send({
      "from": "Juicy Meets <onboarding@resend.dev>",
      "to": [user.email],
      "subject": "Juicy Meets - Your New Password",
      "html": html_content,
      "text": text_content
    })

    Rails.logger.info "Forgot password email sent successfully: #{result[:id]}"
    result
  end
end
