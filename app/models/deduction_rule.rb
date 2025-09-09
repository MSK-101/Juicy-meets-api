class DeductionRule < ApplicationRecord
  # Constants
  DEDUCTION_TYPES = %w[duration per_swipe].freeze

  # Validations
  validates :deduction_type, presence: true, inclusion: { in: DEDUCTION_TYPES }
  validates :coins, presence: true, numericality: { only_integer: true, greater_than: 0 }

  # Duration-based rules need threshold_seconds and must be unique
  validates :threshold_seconds, presence: true, numericality: { only_integer: true, greater_than: 0 },
            if: :duration_based?
  validates :threshold_seconds, uniqueness: { scope: :deduction_type }, if: :duration_based?

  # Per-swipe rules don't need threshold_seconds
  validates :threshold_seconds, absence: true, if: :per_swipe?

  # Scopes
  scope :active, -> { where(active: true) }
  scope :duration_based, -> { where(deduction_type: 'duration') }
  scope :per_swipe, -> { where(deduction_type: 'per_swipe') }
  scope :ordered, -> { order(:threshold_seconds, :id) }

  # Methods
  def duration_based?
    deduction_type == 'duration'
  end

  def per_swipe?
    deduction_type == 'per_swipe'
  end

  # Ensure only one active per-swipe rule at a time
  before_save :ensure_single_per_swipe_rule, if: :per_swipe?

  private

  def ensure_single_per_swipe_rule
    if active? && per_swipe?
      # Deactivate other per-swipe rules
      DeductionRule.where(deduction_type: 'per_swipe')
                   .where.not(id: id)
                   .update_all(active: false)
    end
  end
end
