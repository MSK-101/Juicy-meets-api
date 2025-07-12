class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :lockable, :timeoutable, :trackable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :omniauthable,
         :jwt_authenticatable, jwt_revocation_strategy: JwtDenylist

  # Enums for profile fields (Rails 8.0 compatible syntax)
  enum :gender, {
    male: 0,
    female: 1,
    non_binary: 2,
    prefer_not_to_say: 3
  }

  enum :interested_in, {
    men: 0,
    women: 1,
    everyone: 2
  }

  # Coin system associations
  has_one :user_coins, dependent: :destroy
  has_many :user_coin_purchases, dependent: :destroy
  has_many :coin_transactions, dependent: :destroy
  has_many :coin_packages, through: :user_coin_purchases

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

  # Coin system methods
  def available_coins
    user_coins&.available_coins || 0
  end

  def has_coins?
    user_coins&.has_coins? || false
  end

  def can_afford_coins?(amount)
    user_coins&.can_afford?(amount) || false
  end

  def deduct_coins_for_video_call(duration_seconds)
    return 0 unless user_coins
    user_coins.deduct_coins_for_video_call(duration_seconds)
  end

  def add_coins(amount, transaction_type = 'bonus', reference = nil)
    user_coins || create_user_coins!
    user_coins.add_coins(amount, transaction_type, reference)
  end

  def deduct_coins(amount, transaction_type = 'deduction', reference = nil)
    return false unless user_coins
    user_coins.deduct_coins(amount, transaction_type, reference)
  end
end
