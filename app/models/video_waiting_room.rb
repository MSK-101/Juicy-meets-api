class VideoWaitingRoom < ApplicationRecord
  # Using string user_id instead of User model for simplicity
  # belongs_to :user
  # belongs_to :partner_user, class_name: 'User', optional: true

  validates :user_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[waiting matched] }

  scope :waiting, -> { where(status: 'waiting', room_id: nil) }
  scope :matched, -> { where(status: 'matched').where.not(room_id: nil) }
end
