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
    })
  end

  def forgot_password_email(user, password)
    require 'resend'
    Resend.api_key = ENV['RESEND_API_KEY']

    Resend::Emails.send({
      "from": "Juicy Meets <onboarding@resend.dev>",
      "to": [user.email],
      "subject": "Juicy Meets - Your New Password"
    })
  end
end
