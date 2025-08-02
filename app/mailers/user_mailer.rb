class UserMailer < ApplicationMailer

  def password_email(user, password)
    @user = user
    @password = password

    mail(
      to: @user.email,
      subject: 'Welcome to Juicy Meets - Your Password'
    )
  end

  def forgot_password_email(user, new_password)
    @user = user
    @new_password = new_password

    mail(
      to: @user.email,
      subject: 'Juicy Meets - Your New Password'
    )
  end
end
