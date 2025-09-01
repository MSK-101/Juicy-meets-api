class ApplicationMailer < ActionMailer::Base
  # Use verified domain in production, fallback for development
  default from: Rails.env.production? ?
    "Juicy Meets <onboarding@resend.dev>" :
    "noreply@juicymeets.com"
  layout "mailer"
end
