class VideoChatSession < ApplicationRecord
  # Associations
  belongs_to :user, optional: true
  belongs_to :partner_user, class_name: 'User', optional: true
  belongs_to :staff_user, class_name: 'User', optional: true
  belongs_to :video, optional: true
  belongs_to :pool, optional: true
  belongs_to :sequence, optional: true

  # Validations
  validates :session_id, presence: true, uniqueness: true
  validates :session_type, inclusion: { in: %w[user_to_user user_to_staff user_to_video] }
  validates :status, inclusion: { in: %w[active completed disconnected] }
  validates :duration_seconds, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true

  # Enums
  enum session_type: { user_to_user: 0, user_to_staff: 1, user_to_video: 2 }
  enum status: { active: 0, completed: 1, disconnected: 2 }

  # Scopes
  scope :active, -> { where(status: 'active') }
  scope :completed, -> { where(status: 'completed') }
  scope :by_pool, ->(pool_id) { where(pool_id: pool_id) }
  scope :by_sequence, ->(sequence_id) { where(sequence_id: sequence_id) }
  scope :by_staff, ->(staff_id) { where(staff_user_id: staff_id) }
  scope :by_video, ->(video_id) { where(video_id: video_id) }
  scope :recent, -> { where('created_at >= ?', 30.days.ago) }

  # Callbacks
  before_create :generate_session_id
  before_create :set_pool_and_sequence

  # Instance methods
  def end_session
    return false if completed? || disconnected?

    self.duration_seconds = ((Time.current - created_at) / 1.second).round
    self.ended_at = Time.current

    case session_type
    when 'user_to_user'
      self.status = 'completed'
    when 'user_to_staff'
      self.status = 'completed'
      update_staff_metrics
    when 'user_to_video'
      self.status = 'completed'
      update_video_metrics
    end

    save!
  end

  def disconnect_session
    return false if completed? || disconnected?

    self.duration_seconds = ((Time.current - created_at) / 1.second).round
    self.ended_at = Time.current
    self.status = 'disconnected'
    save!
  end

  def is_staff_session?
    user_to_staff?
  end

  def is_video_session?
    user_to_video?
  end

  def is_user_session?
    user_to_user?
  end

  # Class methods for analytics
  def self.staff_performance_stats(staff_id, days: 30)
    sessions = by_staff(staff_id).recent

    {
      total_sessions: sessions.count,
      total_duration: sessions.sum(:duration_seconds),
      average_duration: sessions.average(:duration_seconds)&.round(2),
      completion_rate: sessions.completed.count.to_f / sessions.count * 100,
      total_users_served: sessions.distinct.count(:user_id)
    }
  end

  def self.video_performance_stats(video_id, days: 30)
    sessions = by_video(video_id).recent

    {
      total_views: sessions.count,
      total_duration: sessions.sum(:duration_seconds),
      average_duration: sessions.average(:duration_seconds)&.round(2),
      completion_rate: sessions.completed.count.to_f / sessions.count * 100
    }
  end

  def self.pool_analytics(pool_id, days: 30)
    sessions = by_pool(pool_id).recent

    {
      total_sessions: sessions.count,
      user_to_user_sessions: sessions.user_to_user.count,
      user_to_staff_sessions: sessions.user_to_staff.count,
      user_to_video_sessions: sessions.user_to_video.count,
      average_duration: sessions.average(:duration_seconds)&.round(2),
      total_unique_users: sessions.distinct.count(:user_id)
    }
  end

  private

  def generate_session_id
    self.session_id = "session_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end

  def set_pool_and_sequence
    return unless user_id.present?

    user = User.find_by(id: user_id)
    return unless user

    self.pool_id = user.pool&.id
    self.sequence_id = user.pool&.sequences&.active&.ordered&.first&.id
  end

  def update_staff_metrics
    return unless staff_user_id.present?

    staff_assignment = StaffAssignment.find_by(user_id: staff_user_id)
    return unless staff_assignment

    staff_assignment.increment!(:total_chats)
    staff_assignment.increment!(:total_chat_time, duration_seconds)
  end

  def update_video_metrics
    return unless video_id.present?
    duration = Time.current - self.started_at

    # Update session with end data
    self.update!(
      ended_at: Time.current,
      duration_seconds: duration.to_i,
      end_reason: 'swiped',
      status: 'completed'
    )
  end
end
