class ApplicationMailer < ActionMailer::Base
  # Use Resend's verified domain until your domain is fully verified
  default from: "Resend <onboarding@resend.dev>"
  layout "mailer"
end
