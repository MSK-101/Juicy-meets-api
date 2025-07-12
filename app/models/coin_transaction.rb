class CoinTransaction < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :coin_package, optional: true
  belongs_to :coin_deduction_rule, optional: true
  belongs_to :user_coin_purchase, optional: true

  # Validations
  validates :transaction_type, presence: true, inclusion: { in: %w[purchase deduction bonus refund] }
  validates :amount, presence: true, numericality: { other_than: 0 }
  validates :balance_after, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :credits, -> { where('amount > 0') }
  scope :debits, -> { where('amount < 0') }
  scope :recent, -> { order(created_at: :desc) }
  scope :by_type, ->(type) { where(transaction_type: type) }

  # Instance methods
  def credit?
    amount > 0
  end

  def debit?
    amount < 0
  end

  def absolute_amount
    amount.abs
  end

  def formatted_amount
    "#{credit? ? '+' : '-'}#{absolute_amount}"
  end

  def transaction_summary
    case transaction_type
    when 'purchase'
      "Purchased #{absolute_amount} coins"
    when 'deduction'
      "Deducted #{absolute_amount} coins"
    when 'bonus'
      "Received #{absolute_amount} bonus coins"
    when 'refund'
      "Refunded #{absolute_amount} coins"
    else
      "#{transaction_type.humanize} #{absolute_amount} coins"
    end
  end

  def to_s
    "#{transaction_summary} - Balance: #{balance_after}"
  end
end
