class Video < ApplicationRecord
  # Enums
  has_one_attached :video_file
  enum gender: { male: 0, female: 1, other: 2 }
  enum status: { active: 0, pending: 1, inactive: 2 }

  # Associations
  belongs_to :sequence
  belongs_to :pool
  belongs_to :admin

  # Validations
  validates :name, presence: true, length: { maximum: 100 }
  validates :gender, presence: true, inclusion: { in: genders.keys }
  validates :status, presence: true, inclusion: { in: statuses.keys }

  # Scopes
  scope :active, -> { where(status: :active) }
  scope :pending, -> { where(status: :pending) }
  scope :inactive, -> { where(status: :inactive) }
  scope :by_gender, ->(gender) { where(gender: gender) }
  scope :ordered, -> { order(:created_at) }

  # Instance methods
  def display_name
    "#{name} (#{gender.humanize})"
  end

  def to_s
    display_name
  end
end
