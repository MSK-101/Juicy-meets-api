class VideoWaitingRoom < ApplicationRecord
  # Restore proper User model associations
  belongs_to :user
  belongs_to :partner_user, class_name: 'User', optional: true
  belongs_to :pool, optional: true
  belongs_to :sequence, optional: true
  belongs_to :video, optional: true

  validates :user_id, presence: true, uniqueness: true
  validates :status, inclusion: { in: %w[waiting matched] }
  validates :session_version, presence: true, if: :matched?

  scope :waiting, -> { where(status: 'waiting', room_id: nil) }
  scope :matched, -> { where(status: 'matched').where.not(room_id: nil) }

  # New scopes for pool-based matching
  scope :by_pool, ->(pool_id) { where(pool_id: pool_id) }
  scope :by_sequence, ->(sequence_id) { where(sequence_id: sequence_id) }
  scope :available_for_matching, -> { waiting.where.not(match_type: 'video') }
  scope :staff_available, -> { waiting.where(match_type: 'staff') }
  scope :real_users_available, -> { waiting.where(match_type: 'real_user') }

  # Instance methods for pool and sequence management
  def user_pool
    return pool_id if pool_id.present?

    # Fallback to user's current pool if not set
    user = User.find_by(id: user_id)
    user&.pool&.id
  end

  def current_sequence
    return sequence_id if sequence_id.present?

    # Fallback to user's current sequence if not set
    user = User.find_by(id: user_id)
    return nil unless user&.pool

    user.pool.sequences.active.ordered.first&.id
  end

  def next_sequence
    return nil unless current_sequence

    user = User.find_by(id: user_id)
    return nil unless user&.pool

    current_seq = user.pool.sequences.find_by(id: current_sequence)
    return nil unless current_seq

    user.next_sequence(current_seq.position)
  end

  def is_staff?
    match_type == 'staff'
  end

  def is_video?
    match_type == 'video'
  end

  def is_real_user?
    match_type == 'real_user'
  end

  def matched?
    status == 'matched'
  end

  # Get video information if this is a video match
  def video_info
    return nil unless is_video? && video_id.present?

    video = Video.find_by(id: video_id)
    return nil unless video

    {
      id: video.id,
      name: video.name,
      url: video.video_file.attached? ? video.video_file.url : nil
    }
  end

  # Get session information for WebRTC signaling
  def session_info
    return nil unless matched?

    {
      room_id: room_id,
      session_version: session_version,
      match_type: match_type,
      is_initiator: is_initiator,
      partner_user_id: partner_user_id
    }
  end
end
