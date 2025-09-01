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

    Resend::Emails.send({
      "from": "Juicy Meets <onboarding@resend.dev>",
      "to": [user.email],
      "subject": "Welcome to Juicy Meets - Your Password"
      "html": render_to_string(template: 'user_mailer/password_email')
    })
  end

  def forgot_password_email(user, password)
    require 'resend'
    Resend.api_key = ENV['RESEND_API_KEY']

    Resend::Emails.send({
      "from": "Juicy Meets <onboarding@resend.dev>",
      "to": [user.email],
      "subject": "Juicy Meets - Your New Password",
      "html": render_to_string(template: 'user_mailer/forgot_password_email')
    })
  end
end
