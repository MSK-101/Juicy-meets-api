class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :omniauthable,
         omniauth_providers: [:google_oauth2]

  # Basic JWT configuration - temporarily disabled
  # :jwt_authenticatable

  # Associations
  has_many :purchases, dependent: :destroy
  has_many :coin_packages, through: :purchases
  has_many :coin_transactions, dependent: :destroy
  has_one :staff_assignment, dependent: :destroy
  has_many :user_ip_addresses, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :coin_balance, numericality: { greater_than_or_equal_to: 0 }

  # Callbacks
  before_save :update_last_activity, if: :status_changed?

  # Enums
  enum role: { user: 0, staff: 1}
  enum status: { offline: 0, online: 1, in_chat: 2, busy: 3 }
  enum gender: { male: 0, female: 1, other: 2 }, _prefix: :gender
  enum interested_in: { male: 0, female: 1, other: 2 }, _prefix: :interested_in
  enum user_status: { pending: 0, active: 1, suspended: 2 }

  # Scopes
  scope :active, -> { where(profile_completed: true) }
  scope :with_coins, -> { where('coin_balance > 0') }
  scope :pool_a, -> { where('coin_balance > 0').where.not(coin_transactions: { id: nil }) }
  scope :pool_b, -> { where('coin_balance > 0').where(coin_transactions: { id: nil }) }
  scope :pool_c, -> { where('coin_balance = 0') }
  scope :online, -> { where(status: [:online, :in_chat]) }
  scope :available_staff, -> { staff.online.where.not(status: [:in_chat, :busy]) }

  # Generate random password for new users
  def self.generate_random_password
    SecureRandom.alphanumeric(8)
  end

  # Send password email
  def send_password_email
    UserMailer.password_email(self, password).deliver_now
  end

  # Free coin distribution logic
  def self.can_give_free_coins_to_ip?(ip_address)
    return false unless ip_address.present?
    !UserIpAddress.ip_used_for_free_coins?(ip_address)
  end

  # Give free coins to user and track IP
  def give_free_coins_and_track_ip!(ip_address)
    return false unless ip_address.present?
    return false if coin_balance > 0

    # Check if IP is eligible
    return false unless User.can_give_free_coins_to_ip?(ip_address)

    # Give coins
    amount = ENV.fetch('FREE_COINS_AMOUNT', '100').to_i
    add_coins(amount, 'free_coins', nil)

    # Track IP
    user_ip_addresses.create!(ip_address: ip_address)

    { success: true, coins_given: amount, message: "Free coins distributed" }
  end

  def is_staff?
    role == 'staff'
  end

  def is_online?
    online? || in_chat?
  end

  def is_busy?
    busy?
  end

  def is_available_for_chat?
    is_staff? && online? && !in_chat? && !busy?
  end

  def pool
    if coin_balance > 0 && coin_transactions.empty?
      #it means he has free coins
      Pool.find_by(name: 'Pool A')
    elsif coin_balance > 0 && coin_transactions.any?
      #it means he has paid coins
      Pool.find_by(name: 'Pool B')
    else
      #it means he has no coins
      Pool.find_by(name: 'Pool C')
    end
  end

  def next_sequence(curr_pos)
    pool.sequences.active.find_by(position: curr_pos + 1) || pool.sequences.active.ordered.first
  end

  # Send forgot password email with new password
  def send_forgot_password_email
    new_password = User.generate_random_password
    update(password: new_password)
    UserMailer.forgot_password_email(self, new_password).deliver_now
  end

  # Instance methods
  def add_coins(amount, reason = 'purchase', reference = nil)
    return false if amount <= 0

    transaction do
      update!(coin_balance: coin_balance + amount)
      coin_transactions.create!(
        amount: amount,
        balance_after: coin_balance,
        transaction_type: 'credit',
        description: reason,
        reference_id: reference&.id,
        reference_type: reference&.class&.name
      )
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def deduct_coins(amount, reason = 'deduction', reference = nil)
    return false if amount <= 0 || coin_balance < amount

    transaction do
      update!(coin_balance: coin_balance - amount)
      coin_transactions.create!(
        amount: amount,
        balance_after: coin_balance,
        transaction_type: 'debit',
        description: reason,
        reference_id: reference&.id,
        reference_type: reference&.class&.name
      )
    end
    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def has_coins?
    coin_balance > 0
  end

  def coins_remaining
    coin_balance
  end

  # Status management methods
  def go_online
    update!(status: :online, last_activity_at: Time.current)
  end

  def go_offline
    update!(status: :offline, last_activity_at: Time.current)
  end

  def start_chat
    update!(status: :in_chat, last_activity_at: Time.current)
  end

  def end_chat
    update!(status: :online, last_activity_at: Time.current)
  end

  def set_busy
    update!(status: :busy, last_activity_at: Time.current)
  end

  def update_activity
    update!(last_activity_at: Time.current)
  end

  private

  def update_last_activity
    self.last_activity_at = Time.current
  end
end
