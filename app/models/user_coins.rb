class UserCoins < ApplicationRecord
  self.table_name = 'user_coins'

  # Associations
  belongs_to :user
  has_many :coin_transactions, dependent: :destroy

  # Validations
  validates :balance, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_earned, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :total_spent, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Callbacks
  before_create :set_last_activity_at
  before_update :set_last_activity_at

  # Scopes
  scope :with_balance, -> { where('balance > 0') }
  scope :recently_active, -> { where('last_activity_at > ?', 7.days.ago) }

  # Instance methods
  def available_coins
    balance
  end

  def has_coins?
    balance > 0
  end

  def can_afford?(amount)
    balance >= amount
  end

  def add_coins(amount, transaction_type = 'bonus', reference = nil)
    return false if amount <= 0

    transaction do
      new_balance = balance + amount
      new_total_earned = total_earned + amount

      update!(
        balance: new_balance,
        total_earned: new_total_earned,
        last_activity_at: Time.current
      )

      # Create transaction record
      coin_transactions.create!(
        transaction_type: transaction_type,
        amount: amount,
        balance_after: new_balance,
        coin_package: reference.is_a?(CoinPackage) ? reference : nil,
        user_coin_purchase: reference.is_a?(UserCoinPurchase) ? reference : nil,
        coin_deduction_rule: reference.is_a?(CoinDeductionRule) ? reference : nil,
        description: "Added #{amount} coins"
      )
    end

    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def deduct_coins(amount, transaction_type = 'deduction', reference = nil)
    return false if amount <= 0 || !can_afford?(amount)

    transaction do
      new_balance = balance - amount
      new_total_spent = total_spent + amount

      update!(
        balance: new_balance,
        total_spent: new_total_spent,
        last_activity_at: Time.current
      )

      # Create transaction record
      coin_transactions.create!(
        transaction_type: transaction_type,
        amount: -amount,
        balance_after: new_balance,
        coin_package: reference.is_a?(CoinPackage) ? reference : nil,
        user_coin_purchase: reference.is_a?(UserCoinPurchase) ? reference : nil,
        coin_deduction_rule: reference.is_a?(CoinDeductionRule) ? reference : nil,
        description: "Deducted #{amount} coins"
      )
    end

    true
  rescue ActiveRecord::RecordInvalid
    false
  end

  def deduct_coins_for_video_call(duration_seconds)
    return 0 if duration_seconds <= 0

    total_deducted = CoinDeductionRule.deduct_coins_for_duration(user, duration_seconds)
    total_deducted
  end

  private

  def set_last_activity_at
    self.last_activity_at = Time.current
  end
end
