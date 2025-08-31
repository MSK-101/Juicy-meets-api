class Api::V1::VideoChatController < ApplicationController
  # before_action :authenticate_user!

  # POST /api/video_chat/join
  # User joins the video chat queue
  def join
    # Find or create a waiting room entry
    waiting_user = VideoWaitingRoom.find_by(user: current_user)

    if waiting_user
      # User already in queue
      render json: { status: 'waiting', message: 'Already in queue' }
      return
    end

    # Add user to waiting room
    VideoWaitingRoom.create!(
      user: current_user,
      joined_at: Time.current,
      status: 'waiting'
    )

    # Try to match with another waiting user
    match_users

    render json: { status: 'waiting', message: 'Joined queue' }
  end

  # GET /api/video_chat/status
  # Check if user has been matched
  def status
    waiting_entry = VideoWaitingRoom.find_by(user: current_user)

    unless waiting_entry
      render json: { status: 'not_in_queue' }
      return
    end

    if waiting_entry.room_id.present?
      # User has been matched
      partner = waiting_entry.partner_user

      # Determine match type based on waiting entry
      match_type = waiting_entry.match_type || 'real_user'

      # For staff matches, we need to determine if the partner is staff
      if match_type == 'real_user' && partner&.role == 'staff'
        match_type = 'staff'
      elsif match_type == 'staff' && partner&.role != 'staff'
        match_type = 'real_user'
      end

      render json: {
        status: 'matched',
        room_id: waiting_entry.room_id,
        match_type: match_type,
        partner: {
          id: partner.id,
          username: partner.username || "User#{partner.id}",
          role: partner.role
        },
        is_initiator: waiting_entry.is_initiator
      }
    else
      render json: { status: 'waiting' }
    end
  end

  # POST /api/video_chat/signal
  # Handle WebRTC signaling between matched users
  def signal
    room_id = params[:room_id]
    signal_type = params[:type] # 'offer', 'answer', 'ice-candidate'
    signal_data = params[:data]
    target_user_id = params[:target_user_id]

    # Validate user is in this room
    waiting_entry = VideoWaitingRoom.find_by(user: current_user, room_id: room_id)
    unless waiting_entry
      render json: { error: 'Not authorized for this room' }, status: 403
      return
    end

    # Send signal to target user via ActionCable
    ActionCable.server.broadcast(
      "video_chat_#{room_id}",
      {
        type: 'webrtc_signal',
        signal_type: signal_type,
        data: signal_data,
        from_user_id: current_user.id,
        target_user_id: target_user_id
      }
    )

    render json: { status: 'sent' }
  end

    # POST /api/video_chat/leave
  # User leaves the video chat
  def leave
    waiting_entry = VideoWaitingRoom.find_by(user: current_user)

    if waiting_entry
      if waiting_entry.room_id.present?
        # User was in a chat, notify partner
        ActionCable.server.broadcast(
          "video_chat_#{waiting_entry.room_id}",
          {
            type: 'user_left',
            user_id: current_user.id
          }
        )

        # Also clean up partner's waiting room entry
        if waiting_entry.partner_user
          partner_entry = VideoWaitingRoom.find_by(user: waiting_entry.partner_user)
          partner_entry&.destroy
        end
      end

      waiting_entry.destroy
    end

    render json: { status: 'left' }
  end

  private

  def match_users
    # Find another waiting user (not current user)
    other_waiting = VideoWaitingRoom.where(status: 'waiting')
                                    .where.not(user: current_user)
                                    .where(room_id: nil)
                                    .order(:joined_at)
                                    .first

    return unless other_waiting

    # Create a simple room ID
    room_id = "room_#{Time.current.to_i}_#{SecureRandom.hex(4)}"

    # Update waiting room entries
    current_waiting = VideoWaitingRoom.find_by(user: current_user)
    current_waiting.update!(
      room_id: room_id,
      partner_user: other_waiting.user,
      status: 'matched',
      is_initiator: true  # First user to join becomes initiator
    )

    other_waiting.update!(
      room_id: room_id,
      partner_user: current_user,
      status: 'matched',
      is_initiator: false
    )

    Rails.logger.info "Matched users #{current_user.id} and #{other_waiting.user.id} in room #{room_id}"
  end
end
