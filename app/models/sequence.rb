class Sequence < ApplicationRecord
  # Associations
  belongs_to :pool
  has_many :videos, dependent: :destroy
  has_many :users, dependent: :nullify
  has_many :staff_assignments, dependent: :nullify
  has_many :video_chat_sessions, dependent: :nullify
  has_many :video_waiting_rooms, dependent: :nullify

  # Constants
  CONTENT_TYPES = %w[recorded_videos app_users staff].freeze

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :video_count, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :active, inclusion: { in: [true, false] }
  validates :position, presence: true, numericality: { greater_than_or_equal_to: 0 }
  validates :content_type, presence: true
  validate :content_type_values

  # Scopes
  scope :active, -> { where(active: true) }
  scope :ordered, -> { order(:position, :created_at) }
  scope :with_content_type, ->(type) { where("? = ANY(content_type)", type) }

  # Instance methods
  def display_name
    name.present? ? name : "#{pool.name} - Sequence #{position}"
  end

  def to_s
    display_name
  end

  def has_content_type?(type)
    content_type.include?(type)
  end

  def content_type_labels
    content_type.map { |type| type.humanize.gsub('_', ' ') }
  end

  def ordered_content_type
    # Define the preferred order
    preferred_order = %w[app_users staff recorded_videos]
    # Sort content_type based on the preferred order
    content_type.sort_by { |type| preferred_order.index(type) || preferred_order.length }
  end

  # Alias for content_types that always returns ordered content types
  def content_types
    ordered_content_type
  end

  private

  def content_type_values
    return if content_type.blank?

    invalid_types = content_type - CONTENT_TYPES
    if invalid_types.any?
      errors.add(:content_type, "contains invalid types: #{invalid_types.join(', ')}")
    end
  end
end
