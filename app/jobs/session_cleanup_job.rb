class SessionCleanupJob < ApplicationJob
  queue_as :default

  # Handle session cleanup in background
  def perform(room_id, user_id)
    session = VideoChatSession.find_by(
      room_id: room_id,
      user_id: user_id,
      status: 'active'
    )

    if session
      session.end_session
      Rails.logger.info "Session #{session.id} ended for user #{user_id} in room #{room_id}"
    end
  rescue => e
    Rails.logger.error "SessionCleanupJob failed for user #{user_id} in room #{room_id}: #{e.message}"
  end
end
