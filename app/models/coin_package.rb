class CoinPackage < ApplicationRecord
  # Associations
  # has_many :user_coin_purchases, dependent: :restrict_with_error
  # has_many :coin_transactions, dependent: :restrict_with_error
  # has_many :users, through: :user_coin_purchases
  has_many :purchases, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :price, presence: true, numericality: { greater_than: 0 }
  validates :coins_count, presence: true, numericality: { greater_than: 0 }
  validates :sort_order, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:sort_order, :price) }

  # Instance methods
  def price_per_coin
    return 0 if coins_count.zero?
    (price / coins_count).round(4)
  end

  def display_name
    "#{name} (#{coins_count} coins)"
  end

  def to_s
    display_name
  end
end
