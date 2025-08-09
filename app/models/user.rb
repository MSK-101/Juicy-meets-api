class User < ApplicationRecord
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :confirmable, :omniauthable, omniauth_providers: [:google_oauth2]

  # Associations
  has_many :purchases, dependent: :destroy
  has_many :coin_packages, through: :purchases
  has_many :coin_transactions, dependent: :destroy

  # Validations
  validates :email, presence: true, uniqueness: true
  validates :coin_balance, numericality: { greater_than_or_equal_to: 0 }

  # Enums
  enum gender: { male: 0, female: 1, other: 2 }
  # enum interested_in: { male: 0, female: 1, both: 2 }
  enum role: { user: 0, admin: 1, moderator: 2 }

  # Scopes
  scope :active, -> { where(profile_completed: true) }
  scope :with_coins, -> { where('coin_balance > 0') }

    # Generate random password for new users
  def self.generate_random_password
    SecureRandom.alphanumeric(8)
  end

    # Send password email
  def send_password_email
    UserMailer.password_email(self, password).deliver_now
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
        transaction_type: 'credit',
        amount: amount,
        balance_after: coin_balance,
        reference_id: reference&.id,
        description: reason
      )
    end
    true
  rescue => e
    Rails.logger.error "Failed to add coins: #{e.message}"
    false
  end

  def deduct_coins(amount, reason = 'usage', reference = nil)
    return false if amount <= 0 || coin_balance < amount

    transaction do
      update!(coin_balance: coin_balance - amount)

      coin_transactions.create!(
        transaction_type: 'debit',
        amount: amount,
        balance_after: coin_balance,
        reference_id: reference&.id,
        description: reason
      )
    end
    true
  rescue => e
    Rails.logger.error "Failed to deduct coins: #{e.message}"
    false
  end

  def has_sufficient_coins?(amount)
    coin_balance >= amount
  end

  def purchase_package(coin_package)
    return false unless coin_package

    transaction do
      purchase = purchases.create!(
        coin_package: coin_package,
        coins_count: coin_package.coins_count,
        price: coin_package.price,
        payment_status: 'completed',
        transaction_id: generate_transaction_id
      )

      add_coins(coin_package.coins_count, 'purchase', purchase)
    end
    true
  rescue => e
    Rails.logger.error "Failed to purchase package: #{e.message}"
    false
  end

  private

  def generate_transaction_id
    "TXN_#{Time.current.to_i}_#{SecureRandom.hex(6).upcase}"
  end
end
