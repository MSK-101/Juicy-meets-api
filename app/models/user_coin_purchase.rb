class UserCoinPurchase < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :coin_package
  has_many :coin_transactions, dependent: :restrict_with_error

  # Enums
  enum payment_status: {
    pending: 'pending',
    completed: 'completed',
    failed: 'failed',
    refunded: 'refunded'
  }

  # Validations
  validates :coins_count, presence: true, numericality: { greater_than: 0 }
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :transaction_id, uniqueness: true, allow_nil: true

  # Callbacks
  before_create :set_purchased_at
  after_create :create_coin_transaction, if: :completed?

  # Scopes
  scope :completed, -> { where(payment_status: 'completed') }
  scope :recent, -> { order(purchased_at: :desc) }

  # Instance methods
  def total_value
    price
  end

  def coins_per_dollar
    return 0 if price.zero?
    (coins_count / price).round(2)
  end

  private

  def set_purchased_at
    self.purchased_at = Time.current
  end

  def create_coin_transaction
    user.user_coins.add_coins(coins_count, 'purchase', self)
  end
end
