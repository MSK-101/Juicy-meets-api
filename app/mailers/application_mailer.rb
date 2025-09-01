class ApplicationMailer < ActionMailer::Base
  # Use Resend's verified domain (working format)
  default from: "Juicy Meets <onboarding@resend.dev>"
  layout "mailer"
end
