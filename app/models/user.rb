class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
        :recoverable, :rememberable, :validatable,
        :jwt_authenticatable, jwt_revocation_strategy: Devise::JWT::RevocationStrategies::Null
        #  :confirmable, :omniauthable,
        #  omniauth_providers: [:google_oauth2]

  # Associations
  has_many :purchases, dependent: :destroy
  has_many :coin_packages, through: :purchases
  has_many :coin_transactions, dependent: :destroy
  has_one :staff_assignment, dependent: :destroy
  has_many :user_ip_addresses, dependent: :destroy
  has_many :video_chat_sessions, dependent: :destroy, foreign_key: :user_id
  has_many :staff_chat_sessions, dependent: :destroy, class_name: 'VideoChatSession', foreign_key: :staff_user_id
  has_many :video_waiting_rooms, dependent: :destroy
  has_many :reports_made, class_name: 'UserReport', foreign_key: :reporter_id, dependent: :destroy
  has_many :reports_received, class_name: 'UserReport', foreign_key: :reported_user_id, dependent: :destroy
  # Validations
  validates :email, presence: true, uniqueness: true
  validates :coin_balance, numericality: { greater_than_or_equal_to: 0 }
  validates :videos_watched_in_current_sequence, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :sequence_total_videos, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :email_not_banned

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

  # Video chat session scopes
  scope :with_video_sessions_in_sequence, ->(sequence_id) {
    joins(:video_chat_sessions)
    .where(video_chat_sessions: { sequence_id: sequence_id })
  }

  # Generate random password for new users
  def self.generate_random_password
    SecureRandom.alphanumeric(8)
  end

  # Send password email
  def send_password_email
    # UserMailer.password_email(self, password).deliver_now
  end

  def pool_id
    pool.id
  end

  def total_online_time
    video_chat_sessions.sum(:duration_seconds)/60.00 || 0
  end

  def purchase_package(coin_package)
    return false unless coin_package

    transaction do
      purchase = purchases.create!(
        coin_package: coin_package,
        coins_count: coin_package.coins_count,
        price: coin_package.price,
        payment_status: 'completed',
        transaction_id: SecureRandom.hex(16)
      )
      add_coins(coin_package.coins_count, 'purchase', purchase)
    end
    true
  rescue => e
    Rails.logger.error "Failed to purchase package: #{e.message}"
    false
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
    if staff_assignment.present?
      return staff_assignment.pool
    end

    if coin_balance > 0 && purchases.blank?
      #it means he has free coins
      Pool.find_by(name: 'Pool A')
    elsif coin_balance > 0
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

  # New method: Get current sequence info
  def current_sequence_info
    return nil unless pool && sequence_id

    sequence = pool.sequences.find_by(id: sequence_id)
    return nil unless sequence

    {
      sequence_id: sequence.id,
      sequence_name: sequence.name,
      sequence_position: sequence.position,
      videos_watched: videos_watched_in_current_sequence || 0,
      total_videos: sequence.video_count,
      progress_percentage: calculate_progress_percentage
    }
  end

  # New method: Calculate progress percentage for current sequence
  def calculate_progress_percentage
    return 0 unless videos_watched_in_current_sequence && sequence_total_videos && sequence_total_videos > 0

    ((videos_watched_in_current_sequence.to_f / sequence_total_videos) * 100).round(2)
  end

  # New method: Check if user is ready for next sequence
  def ready_for_next_sequence?
    return false unless videos_watched_in_current_sequence && sequence_total_videos

    videos_watched_in_current_sequence >= sequence_total_videos
  end

  # New method: Reset video count for new sequence
  def reset_video_count_for_new_sequence
    update!(videos_watched_in_current_sequence: 0)
  end

  # New method: Update sequence info
  def update_sequence_info(sequence_id, total_videos)
    update!(
      sequence_id: sequence_id,
      sequence_total_videos: total_videos,
      videos_watched_in_current_sequence: 0
    )
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
    debugger
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

  def active?
    video_waiting_rooms.present? || video_chat_sessions.where(status: :active).present? || staff_chat_sessions.where(status: :active).present?
  end

  # Report functionality
  def report_user(reported_user_id)
    return { success: false, message: "Cannot report yourself" } if id == reported_user_id

    reported_user = User.find_by(id: reported_user_id)
    return { success: false, message: "User not found" } unless reported_user

    existing_report = reports_made.find_by(reported_user_id: reported_user_id)
    return { success: false, message: "Already reported this user" } if existing_report

    reports_made.create!(reported_user_id: reported_user_id)
    block_user(reported_user_id)

    { success: true, message: "User reported successfully" }
  rescue ActiveRecord::RecordInvalid => e
    { success: false, message: e.message }
  end

  def block_user(user_id)
    return false if id == user_id

    blocked_users << user_id.to_s unless blocked_users.include?(user_id.to_s)
    save!
  end

  def unblock_user(user_id)
    blocked_users.delete(user_id.to_s)
    save!
  end

  def blocked_user?(user_id)
    blocked_users.include?(user_id.to_s)
  end

  def is_banned?
    user_status == 'suspended'
  end

  def ban_user!
    update!(user_status: :suspended)
  end

  def unban_user!
    update!(user_status: :active)
  end

  def status
    active? ? :online : :offline
  end

  # Check if email is banned (prevent banned users from creating new accounts)
  def email_not_banned
    return unless email.present?

    # Check if this email was used by a banned user
    banned_user = User.where(email: email, user_status: :suspended).where.not(id: id).first
    if banned_user
      errors.add(:email, "This email is associated with a banned account. Please contact support.")
    end
  end

  # Class method to check if email is banned
  def self.email_banned?(email)
    User.where(email: email, user_status: :suspended).exists?
  end

  # Get watched video IDs in a specific sequence
  def watched_video_ids_in_sequence(sequence_id)
    video_chat_sessions.where(sequence_id: sequence_id).pluck(:video_id).uniq
  end

  # Get video with oldest chat session in a specific sequence
  def video_with_oldest_session_in_sequence(sequence_id)
    oldest_session = video_chat_sessions
      .where(sequence_id: sequence_id)
      .joins(:video)
      .where(videos: { status: :active })
      .order(:created_at)
      .first

    oldest_session&.video
  end

  private

  def update_last_activity
    self.last_activity_at = Time.current
  end
end
