class Sequence < ApplicationRecord
  # Associations
  belongs_to :pool
  has_many :videos, dependent: :destroy

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :video_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [true, false] }
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }

  # Scopes
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :created_at) }

  # Instance methods
  def display_name
    name.present? ? name : "#{pool.name} - Sequence #{position}"
  end

  def to_s
    display_name
  end
end
