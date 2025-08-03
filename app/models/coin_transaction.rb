class CoinTransaction < ApplicationRecord
  # Associations
  belongs_to :user

  # Enums
  enum transaction_type: {
    credit: 'credit',
    debit: 'debit'
  }

  # Validations
  validates :amount, presence: true, numericality: { greater_than: 0 }
  validates :balance_after, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :transaction_type, presence: true

  # Scopes
  scope :credits, -> { where(transaction_type: 'credit') }
  scope :debits, -> { where(transaction_type: 'debit') }
  scope :recent, -> { order(created_at: :desc) }

  # Instance methods
  def credit?
    transaction_type == 'credit'
  end

  def debit?
    transaction_type == 'debit'
  end

  def formatted_amount
    "#{credit? ? '+' : '-'}#{amount}"
  end

  def formatted_balance
    balance_after
  end
end
