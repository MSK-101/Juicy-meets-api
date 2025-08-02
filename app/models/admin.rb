class Admin < ApplicationRecord
  has_secure_password

  # Enums
  enum role: {
    super_admin: 0,
    admin: 1,
    moderator: 2
  }

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 6 }, if: :password_required?
  validates :role, presence: true

  # Scopes
  scope :active, -> { where(active: true) }

  # Methods
  def display_name
    email.split('@').first
  end

  def can_manage_admins?
    super_admin? || admin?
  end

  def can_moderate?
    super_admin? || admin? || moderator?
  end

  private

  def password_required?
    new_record? || password.present?
  end
end
