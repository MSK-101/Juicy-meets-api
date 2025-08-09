class DeductionRule < ApplicationRecord
  # Validations
  validates :threshold_seconds, presence: true, numericality: { only_integer: true, greater_than: 0 }, uniqueness: true
  validates :coins, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:threshold_seconds, :id) }
end
