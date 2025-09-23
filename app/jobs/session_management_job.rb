class SessionManagementJob < ApplicationJob
  queue_as :default

  # Handle session creation in background
  def perform(user_id, match_result)
    matching_service = PoolMatchingAdapter.new(user_id)
    matching_service.create_session(match_result)
  rescue => e
    Rails.logger.error "SessionManagementJob failed for user #{user_id}: #{e.message}"
    # Don't re-raise to prevent job retries for session creation failures
  end
end
