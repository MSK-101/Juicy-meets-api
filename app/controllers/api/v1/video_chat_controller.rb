class Api::V1::VideoChatController < ApplicationController
  # Require authentication for video chat
  before_action :authenticate_user!

  # Using PubNub for signaling - no server-side signal storage needed
  # Include coin deduction service for connection costs

  # POST /api/video_chat/join
  # User joins the video chat queue
  def join
    user_id = current_user.id

    # Find or create a waiting room entry
    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    if waiting_entry && waiting_entry.status == 'waiting'
      # User already in queue, return current status
      render json: { status: 'already_in_queue' }
      return
    end

    # Clean up any old entries for this user
    VideoWaitingRoom.where(user_id: user_id).destroy_all

    # Get user's pool and sequence information
    user = User.find(user_id)
    pool = user.pool
    sequence = user.pool&.sequences&.active&.ordered&.first
    match_type = user.role == 'staff' ? 'staff' : 'real_user'
    # Create new waiting room entry with pool and sequence info
    waiting_entry = VideoWaitingRoom.create!(
      user_id: user_id,
      pool_id: pool&.id,
      sequence_id: sequence&.id,
      joined_at: Time.current,
      status: 'waiting',
      match_type: match_type
    )

    # Try to find a match using the pool matching service
    matching_service = PoolMatchingService.new(user_id)
    match_result = matching_service.find_match

    if match_result[:success]
      # Create session for tracking
      session = matching_service.create_session(match_result)

      render json: {
        status: 'matched',
        room_id: match_result[:room_id],
        match_type: match_result[:match_type],
        actual_match_type: match_result[:actual_match_type],  # Add actual match type for frontend logic
        partner: {
          id: match_result[:partner_id] || 'video',
          type: match_result[:match_type]
        },
        is_initiator: match_result[:is_initiator],
        session_id: session&.session_id,
        session_version: match_result[:session_version],
        video_id: match_result[:video_id],
        video_url: match_result[:video_url],
        video_name: match_result[:video_name]
      }
    else
      render json: { status: 'joined_queue', user_id: user_id, message: match_result[:message] }
    end
  end

  # GET /api/video_chat/status
  # Check if user has been matched
  def status
    user_id = current_user.id
    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    Rails.logger.info "🔍 Status check for user #{user_id}"
    Rails.logger.info "🔍 Waiting entry: #{waiting_entry.inspect}"

    unless waiting_entry
      Rails.logger.info "❌ No waiting entry found for user #{user_id}"
      render json: { status: 'not_in_queue' }
      return
    end

    if waiting_entry.room_id.present?
      # User has been matched - DO NOT call find_match again!
      Rails.logger.info "✅ User #{user_id} already matched with room #{waiting_entry.room_id}, type: #{waiting_entry.match_type}"
      Rails.logger.info "🔒 User is in active connection - returning current match status"

      # Get the user's actual role for proper match_type
      user = User.find(user_id)
      user_match_type = user.role == 'staff' ? 'staff' : 'real_user'

      Rails.logger.info "🔍 User #{user_id} role: #{user.role}, returning match_type: #{user_match_type}"

      # Determine actual match type based on room's match_type and user roles
      actual_match_type = case waiting_entry.match_type
      when 'video'
        'video'
      when 'real_user'
        # Check if this is actually a staff match by looking at partner
        if waiting_entry.partner_user_id
          partner_user = User.find_by(id: waiting_entry.partner_user_id)
          partner_user&.role == 'staff' ? 'staff' : 'real_user'
        else
          'real_user'
        end
      else
        waiting_entry.match_type
      end

      render json: {
        status: 'matched',
        room_id: waiting_entry.room_id,
        match_type: user_match_type,  # Use user's role, not room's match_type
        actual_match_type: actual_match_type,  # Add actual match type for frontend logic
        partner: {
          id: waiting_entry.partner_user_id || 'video',
          type: waiting_entry.match_type  # Keep partner type as room's match_type
        },
        is_initiator: waiting_entry.is_initiator,
        session_version: waiting_entry.session_version,
        video_id: waiting_entry.video_id,
        video_url: waiting_entry.video_info&.dig(:url),
        video_name: waiting_entry.video_info&.dig(:name)
      }
      return  # Explicitly return to prevent any further processing
    end

    # Check if we should try to find a match now
    Rails.logger.info "🔄 No room_id yet, trying to find match for user #{user_id}"
    matching_service = PoolMatchingService.new(user_id)
    match_result = matching_service.find_match

    if match_result[:success]
      # Create session for tracking
      session = matching_service.create_session(match_result)

      # Get the user's actual role for proper match_type
      user = User.find(user_id)
      user_match_type = user.role == 'staff' ? 'staff' : 'real_user'

      Rails.logger.info "✅ Found match for user #{user_id}: #{match_result.inspect}"
      Rails.logger.info "🔍 User #{user_id} role: #{user.role}, returning match_type: #{user_match_type}"

      render json: {
        status: 'matched',
        room_id: match_result[:room_id],
        match_type: user_match_type,  # Use user's role, not room's match_type
        actual_match_type: match_result[:actual_match_type],  # Add actual match type for frontend logic
        partner: {
          id: match_result[:partner_id] || 'video',
          type: match_result[:match_type]  # Keep partner type as room's match_type
        },
        is_initiator: match_result[:is_initiator],
        session_id: session&.session_id,
        session_version: match_result[:session_version],
        video_id: match_result[:video_id],
        video_url: match_result[:video_url],
        video_name: match_result[:video_name]
      }
    else
      Rails.logger.info "⏳ No match found for user #{user_id}: #{match_result[:message]}"
      render json: { status: 'waiting', message: match_result[:message] }
    end
  end

  # Note: WebRTC signaling now handled by PubNub on frontend
  # No server-side signal endpoints needed

  # GET /api/video_chat/deduction_rules
  # Get active deduction rules for frontend
  def deduction_rules
    active_rules = DeductionRule.active.ordered.map do |rule|
      {
        id: rule.id,
        name: rule.name,
        threshold_seconds: rule.threshold_seconds,
        coins: rule.coins
      }
    end

    render json: { rules: active_rules }
  end

  # POST /api/video_chat/apply_duration_deduction
  # Apply duration-based deductions when chat reaches thresholds
  def apply_duration_deduction
    user_id = current_user.id
    chat_duration_seconds = params[:chat_duration_seconds].to_i

    if chat_duration_seconds <= 0
      render json: { error: 'Invalid chat duration' }, status: :bad_request
      return
    end

    result = CoinDeductionService.apply_duration_based_deductions(user_id, chat_duration_seconds)

    if result[:success]
      render json: {
        success: true,
        deducted: result[:deducted],
        new_balance: result[:new_balance],
        applied_rules: result[:applied_rules],
        chat_duration: result[:chat_duration]
      }
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  # GET /api/video_chat/user_balance
  # Get current user's coin balance
  def user_balance
    result = CoinDeductionService.get_user_balance(current_user.id)

    if result[:success]
      render json: { balance: result[:balance] }
    else
      render json: { error: result[:error] }, status: :unprocessable_entity
    end
  end

  # POST /api/video_chat/leave
  # User leaves the video chat
  def leave
    user_id = current_user.id

    Rails.logger.info "👋 User #{user_id} leaving video chat"

    # Use the pool matching service for proper cleanup
    matching_service = PoolMatchingService.new(user_id)

    # Clean up any stale room assignments first
    matching_service.cleanup_stale_room_assignments

    # Handle room disconnection if user is in a room
    matching_service.handle_room_disconnection

    # Find and clean up all waiting room entries for this user
    waiting_entries = VideoWaitingRoom.where(user_id: user_id)

    waiting_entries.each do |waiting_entry|
      if waiting_entry.room_id.present?
        # End the current session
        end_current_session(waiting_entry.room_id, user_id)

        Rails.logger.info "✅ Ended session for room #{waiting_entry.room_id}"
      end

      # Destroy the waiting entry
      waiting_entry.destroy
      Rails.logger.info "✅ Cleaned up waiting entry for user #{user_id}"
    end

    # Also clean up any VideoChatSessions that might be active
    active_sessions = VideoChatSession.where(user_id: user_id, status: 'active')
    active_sessions.update_all(
      status: 'completed',
      ended_at: Time.current,
      end_reason: 'user_left'
    )

    Rails.logger.info "✅ User #{user_id} completely disconnected from video chat"

    render json: { status: 'left' }
  end

  # POST /api/video_chat/swipe
  # User swipes to get next match
  def swipe
    user_id = current_user.id
    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    unless waiting_entry
      render json: { error: 'User not in queue' }, status: :bad_request
      return
    end

    # Try to find next match (service will handle room cleanup automatically)
    matching_service = PoolMatchingService.new(user_id)
    match_result = matching_service.find_next_match

    if match_result[:success]
      # Create session for tracking
      session = matching_service.create_session(match_result)

      # Get updated user info after potential sequence advancement
      updated_user_info = matching_service.get_updated_sequence_info

      render json: {
        status: 'matched',
        room_id: match_result[:room_id],
        match_type: match_result[:match_type],
        actual_match_type: match_result[:actual_match_type],  # Add actual match type for frontend logic
        partner: {
          id: match_result[:partner_id] || 'video',
          type: match_result[:match_type]
        },
        is_initiator: match_result[:is_initiator],
        session_id: session&.session_id,
        session_version: match_result[:session_version],
        video_id: match_result[:video_id],
        video_url: match_result[:video_url],
        video_name: match_result[:video_name],
        updated_user_info: updated_user_info
      }
    else
      render json: { status: 'waiting', message: match_result[:message] }
    end
  end

      # POST /api/video_chat/end_session
  # End current video chat session
  def end_session
    user_id = current_user.id
    room_id = params[:room_id]

    unless room_id
      render json: { error: 'Room ID required' }, status: :bad_request
      return
    end

    # End the session
    end_current_session(room_id, user_id)

    render json: { status: 'session_ended' }
  end

  # POST /api/video_chat/clear_waiting_room
  # Clear waiting room after successful WebRTC connection
  def clear_waiting_room
    user_id = current_user.id
    room_id = params[:room_id]

    unless room_id
      render json: { error: 'Room ID required' }, status: :bad_request
      return
    end

    Rails.logger.info "🧹 Clearing waiting room for room #{room_id} by user #{user_id}"

    begin
      # Find all waiting room entries for this room
      waiting_entries = VideoWaitingRoom.where(room_id: room_id)

      if waiting_entries.empty?
        Rails.logger.warn "⚠️ No waiting room entries found for room #{room_id}"
        render json: { success: false, message: 'No waiting room entries found' }
        return
      end

      # Update status to 'completed' and add completion timestamp
      waiting_entries.update_all(
        status: 'completed',
        completed_at: Time.current,
        updated_at: Time.current
      )

      Rails.logger.info "✅ Successfully cleared waiting room for room #{room_id}. Updated #{waiting_entries.count} entries."

      render json: {
        success: true,
        message: 'Waiting room cleared successfully',
        room_id: room_id,
        entries_updated: waiting_entries.count
      }
    rescue => e
      Rails.logger.error "❌ Error clearing waiting room for room #{room_id}: #{e.message}"
      render json: {
        success: false,
        error: 'Failed to clear waiting room',
        message: e.message
      }, status: :internal_server_error
    end
  end

  private

  def end_current_session(room_id, user_id)
    # Find and end the current session
    session = VideoChatSession.find_by(
      room_id: room_id,
      user_id: user_id,
      status: 'active'
    )

    if session
      session.end_session
      Rails.logger.info "✅ Session #{session.session_id} ended for user #{user_id}"
    end
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
      is_initiator: true  # First user to become initiator
    )

    other_waiting.update!(
      room_id: room_id,
      partner_user_id: current_user_id,
      status: 'matched',
      is_initiator: false
    )

    Rails.logger.info "Matched users #{current_user_id} and #{other_waiting.user_id} in room #{room_id}"

    # Apply initial connection cost deduction for both users
    begin
      # Deduct 1 coin from current user
      current_deduction = CoinDeductionService.deduct_initial_connection_cost(current_user_id)
      if current_deduction[:success]
        Rails.logger.info "💰 Initial connection cost deducted from user #{current_user_id}: #{current_deduction[:deducted]} coin"
      else
        Rails.logger.warn "⚠️ Failed to deduct initial connection cost from user #{current_user_id}: #{current_deduction[:error]}"
      end

      # Deduct 1 coin from partner user
      partner_deduction = CoinDeductionService.deduct_initial_connection_cost(other_waiting.user_id)
      if partner_deduction[:success]
        Rails.logger.info "💰 Initial connection cost deducted from user #{other_waiting.user_id}: #{partner_deduction[:deducted]} coin"
      else
        Rails.logger.warn "⚠️ Failed to deduct initial connection cost from user #{other_waiting.user_id}: #{partner_deduction[:error]}"
      end
    rescue => e
      Rails.logger.error "❌ Error applying initial connection deductions: #{e.message}"
    end
  end
end
