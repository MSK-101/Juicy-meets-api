class CoinDeductionRule < ApplicationRecord
  # Associations
  has_many :coin_transactions, dependent: :restrict_with_error

  # Validations
  validates :name, presence: true, length: { maximum: 100 }, uniqueness: true
  validates :duration_seconds, presence: true, numericality: { greater_than: 0 }
  validates :coins_deducted, presence: true, numericality: { greater_than: 0 }
  validates :sort_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_order, :duration_seconds) }

  # Instance methods
  def duration_minutes
    (duration_seconds / 60.0).round(2)
  end

  def coins_per_minute
    return 0 if duration_seconds.zero?
    (coins_deducted / (duration_seconds / 60.0)).round(2)
  end

  def display_name
    "#{name} (#{coins_deducted} coins per #{duration_minutes} min)"
  end

  def to_s
    display_name
  end

  # Class methods for deduction logic
  def self.deduct_coins_for_duration(user, duration_seconds)
    return 0 if duration_seconds <= 0

    total_coins_deducted = 0
    active_rules = active.ordered

    active_rules.each do |rule|
      # Calculate how many times this rule applies
      times_applied = (duration_seconds / rule.duration_seconds).floor
      coins_for_this_rule = times_applied * rule.coins_deducted

      if coins_for_this_rule > 0
        user.user_coins.deduct_coins(coins_for_this_rule, 'deduction', rule)
        total_coins_deducted += coins_for_this_rule
      end
    end

    total_coins_deducted
  end
end
