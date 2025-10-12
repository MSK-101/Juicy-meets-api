class UserReport < ApplicationRecord
  belongs_to :reporter, class_name: 'User'
  belongs_to :reported_user, class_name: 'User'

  validates :reporter_id, presence: true
  validates :reported_user_id, presence: true
  validate :cannot_report_self
  validate :unique_report_per_pair

  after_create :increment_reported_user_report_count_and_check_ban

  private

  def cannot_report_self
    errors.add(:reported_user_id, "cannot report yourself") if reporter_id == reported_user_id
  end

  def unique_report_per_pair
    existing_report = UserReport.where(
      reporter_id: reporter_id,
      reported_user_id: reported_user_id
    ).where.not(id: id)

    errors.add(:reported_user_id, "already reported this user") if existing_report.exists?
  end

  def increment_reported_user_report_count_and_check_ban
    reported_user.increment!(:report_count)
    reported_user.reload

    # Only auto-ban real users, not staff or videos
    if reported_user.report_count >= 5 && reported_user.role == 'user'
      reported_user.update!(user_status: :suspended)

      # Log out the banned user by invalidating their JWT token
      invalidate_user_tokens(reported_user)
    end
  end

  private

  def invalidate_user_tokens(user)
    # Invalidate all JWT tokens for the banned user
    # This will force them to re-authenticate on next request
    begin
      # Clear any stored tokens or sessions
      # Since we're using JWT with no revocation strategy, we'll rely on frontend logout
      Rails.logger.info "User #{user.id} (#{user.email}) has been banned and should be logged out"

      # You could also add a banned_at timestamp or token blacklist here
      # For now, the frontend will handle the logout when it detects the suspended status
    rescue => e
      Rails.logger.error "Failed to invalidate tokens for banned user #{user.id}: #{e.message}"
    end
  end
end
