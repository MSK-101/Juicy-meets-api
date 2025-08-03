class Pool < ApplicationRecord
  # Associations
  has_many :sequences, dependent: :destroy
  has_many :videos, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :active, inclusion: { in: [true, false] }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:created_at) }

  # Instance methods
  def display_name
    name
  end

  def to_s
    display_name
  end
end
