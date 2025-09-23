class UserInfoUpdateJob < ApplicationJob
  queue_as :default

  # Handle user info updates in background
  def perform(user_id)
    matching_service = PoolMatchingAdapter.new(user_id)
    updated_info = matching_service.get_updated_sequence_info

    # You could broadcast this via ActionCable or WebSocket if needed
    # ActionCable.server.broadcast("user_#{user_id}", {
    #   type: 'user_info_updated',
    #   data: updated_info
    # })

    Rails.logger.info "User info updated for user #{user_id}: #{updated_info}"
  rescue => e
    Rails.logger.error "UserInfoUpdateJob failed for user #{user_id}: #{e.message}"
  end
end
