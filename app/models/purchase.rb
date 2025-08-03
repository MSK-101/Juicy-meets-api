class Purchase < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :coin_package

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

  def refund!
    return false unless completed?

    transaction do
      update!(payment_status: 'refunded')
      user.deduct_coins(coins_count, 'refund', self)
    end
    true
  rescue => e
    Rails.logger.error "Failed to refund purchase: #{e.message}"
    false
  end

  private

  def set_purchased_at
    self.purchased_at = Time.current
  end
end
