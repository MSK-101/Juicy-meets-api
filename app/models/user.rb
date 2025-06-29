class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :trackable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :omniauthable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  # Enums for profile fields
  enum gender: {
    male: 0,
    female: 1,
    non_binary: 2,
    prefer_not_to_say: 3
  }

  enum interested_in: {
    men: 0,
    women: 1,
    everyone: 2
  }

  # Validations
  validates :age, presence: true, numericality: { greater_than_or_equal_to: 18, less_than_or_equal_to: 100 }, if: :profile_completed?
  validates :gender, presence: true, if: :profile_completed?
  validates :interested_in, presence: true, if: :profile_completed?

  # Scopes
  scope :profile_completed, -> { where(profile_completed: true) }
  scope :profile_incomplete, -> { where(profile_completed: false) }

  # OAuth methods
  def self.from_omniauth(auth)
    where(email: auth.info.email).first_or_create do |user|
      user.email = auth.info.email
      user.password = Devise.friendly_token[0, 20]
      user.provider = auth.provider
      user.uid = auth.uid
      # OAuth users are automatically confirmed
      user.confirmed_at = Time.current
      user.skip_confirmation!
    end
  end

  def oauth_user?
    provider.present? && uid.present?
  end

  # Methods
  def profile_complete?
    age.present? && gender.present? && interested_in.present?
  end

  def complete_profile!
    update!(profile_completed: true) if profile_complete?
  end

  # Email confirmation methods
  def confirmed?
    confirmed_at.present?
  end

  def confirmation_pending?
    !confirmed? && confirmation_token.present?
  end

  def confirmation_required_for_signed_in?
    !confirmed?
  end

  # Override active_for_authentication to require confirmation (except for OAuth users)
  def active_for_authentication?
    super && (confirmed? || oauth_user?)
  end

  # Custom message when user is not confirmed
  def inactive_message
    (confirmed? || oauth_user?) ? super : :unconfirmed
  end
end
