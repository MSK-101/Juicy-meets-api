class ApplicationMailer < ActionMailer::Base
  # Use your verified domain for both environments
  default from: "Juicy Meets <noreply@juicymeets.com>"
  layout "mailer"
end
