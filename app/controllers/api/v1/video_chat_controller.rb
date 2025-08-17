class Api::V1::VideoChatController < ApplicationController
  # Skip authentication for now - using random user IDs
  # before_action :authenticate_user!

  # Using PubNub for signaling - no server-side signal storage needed

  # POST /api/video_chat/join
  # User joins the video chat queue
  def join
    user_id = get_or_create_user_id

    # Find or create a waiting room entry
    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    if waiting_entry && waiting_entry.status == 'waiting'
      # User already in queue, return current status
      render json: { status: 'already_in_queue' }
      return
    end

    # Clean up any old entries for this user
    VideoWaitingRoom.where(user_id: user_id).destroy_all

    # Create new waiting room entry
    VideoWaitingRoom.create!(
      user_id: user_id,
      joined_at: Time.current,
      status: 'waiting'
    )

    # Try to match with another waiting user
    match_users(user_id)

    render json: { status: 'joined_queue', user_id: user_id }
  end

  # GET /api/video_chat/status
  # Check if user has been matched
  def status
    user_id = get_or_create_user_id
    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    unless waiting_entry
      render json: { status: 'not_in_queue' }
      return
    end

    if waiting_entry.room_id.present?
      # User has been matched
      render json: {
        status: 'matched',
        room_id: waiting_entry.room_id,
        partner: {
          id: waiting_entry.partner_user_id,
          username: "User#{waiting_entry.partner_user_id}"
        },
        is_initiator: waiting_entry.is_initiator
      }
    else
      render json: { status: 'waiting' }
    end
  end

  # Note: WebRTC signaling now handled by PubNub on frontend
  # No server-side signal endpoints needed

  # POST /api/video_chat/leave
  # User leaves the video chat
  def leave
    user_id = get_or_create_user_id
    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    if waiting_entry
      if waiting_entry.room_id.present?
        # User was in a chat, notify partner
        ActionCable.server.broadcast(
          "video_chat_#{waiting_entry.room_id}",
          {
            type: 'user_left',
            user_id: user_id
          }
        )

        # Also clean up partner's waiting room entry
        if waiting_entry.partner_user_id
          partner_entry = VideoWaitingRoom.find_by(user_id: waiting_entry.partner_user_id)
          partner_entry&.destroy
        end
      end

      waiting_entry.destroy
    end

    render json: { status: 'left' }
  end

  private

  def get_or_create_user_id
    # Try to get user ID from header first, then session, then create new
    user_id = request.headers['X-User-ID'] || session[:user_id]

    unless user_id
      user_id = "user_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
      session[:user_id] = user_id
    end

    user_id
  end

  def match_users(current_user_id)
    # Find another waiting user (not current user)
    other_waiting = VideoWaitingRoom.where(status: 'waiting')
                                    .where.not(user_id: current_user_id)
                                    .where(room_id: nil)
                                    .order(:joined_at)
                                    .first

    return unless other_waiting

    # Create a simple room ID
    room_id = "room_#{Time.current.to_i}_#{SecureRandom.hex(4)}"

    # Update waiting room entries
    current_waiting = VideoWaitingRoom.find_by(user_id: current_user_id)
    current_waiting.update!(
      room_id: room_id,
      partner_user_id: other_waiting.user_id,
      status: 'matched',
      is_initiator: true  # First user to join becomes initiator
    )

    other_waiting.update!(
      room_id: room_id,
      partner_user_id: current_user_id,
      status: 'matched',
      is_initiator: false
    )

    Rails.logger.info "Matched users #{current_user_id} and #{other_waiting.user_id} in room #{room_id}"
  end
end
