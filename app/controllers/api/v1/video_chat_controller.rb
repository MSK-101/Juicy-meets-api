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

    # Create new waiting room entry with pool and sequence info
    waiting_entry = VideoWaitingRoom.create!(
      user_id: user_id,
      pool_id: pool&.id,
      sequence_id: sequence&.id,
      joined_at: Time.current,
      status: 'waiting',
      match_type: 'real_user'
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
        partner: {
          id: match_result[:partner_id] || 'video',
          type: match_result[:match_type]
        },
        is_initiator: match_result[:is_initiator],
        session_id: session&.session_id,
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
      # User has been matched
      Rails.logger.info "✅ User #{user_id} matched with room #{waiting_entry.room_id}, type: #{waiting_entry.match_type}"
      render json: {
        status: 'matched',
        room_id: waiting_entry.room_id,
        match_type: waiting_entry.match_type,
        partner: {
          id: waiting_entry.partner_user_id || 'video',
          type: waiting_entry.match_type
        },
        is_initiator: waiting_entry.is_initiator,
        video_id: waiting_entry.video_id,
        video_url: waiting_entry.video_info&.dig(:url),
        video_name: waiting_entry.video_info&.dig(:name)
      }
    else
      # Check if we should try to find a match now
      Rails.logger.info "🔄 No room_id yet, trying to find match for user #{user_id}"
      matching_service = PoolMatchingService.new(user_id)
      match_result = matching_service.find_match

      if match_result[:success]
        # Create session for tracking
        session = matching_service.create_session(match_result)

        Rails.logger.info "✅ Found match for user #{user_id}: #{match_result.inspect}"
        render json: {
          status: 'matched',
          room_id: match_result[:room_id],
          match_type: match_result[:match_type],
          partner: {
            id: match_result[:partner_id] || 'video',
            type: match_result[:match_type]
          },
          is_initiator: match_result[:is_initiator],
          session_id: session&.session_id,
          video_id: match_result[:video_id],
          video_url: match_result[:video_url],
          video_name: match_result[:video_name]
        }
      else
        Rails.logger.info "⏳ No match found for user #{user_id}: #{match_result[:message]}"
        render json: { status: 'waiting', message: match_result[:message] }
      end
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
    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    if waiting_entry
      if waiting_entry.room_id.present?
        # End the current session
        end_current_session(waiting_entry.room_id, user_id)

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

  # POST /api/video_chat/swipe
  # User swipes to get next match
  def swipe
    user_id = current_user.id
    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    unless waiting_entry
      render json: { error: 'User not in queue' }, status: :bad_request
      return
    end

    # End current session if exists
    if waiting_entry.room_id.present?
      end_current_session(waiting_entry.room_id, user_id)

      # Clean up partner's waiting room entry
      if waiting_entry.partner_user_id
        partner_entry = VideoWaitingRoom.find_by(user_id: waiting_entry.partner_user_id)
        partner_entry&.destroy
      end
    end

    # Reset waiting entry for next match
    waiting_entry.update!(
      room_id: nil,
      partner_user_id: nil,
      status: 'waiting',
      match_type: 'real_user'
    )

    # Try to find next match
    matching_service = PoolMatchingService.new(user_id)
    match_result = matching_service.find_next_match

    if match_result[:success]
      # Create session for tracking
      session = matching_service.create_session(match_result)

      render json: {
        status: 'matched',
        room_id: match_result[:room_id],
        match_type: match_result[:match_type],
        partner: {
          id: match_result[:partner_id] || 'video',
          type: match_result[:match_type]
        },
        is_initiator: match_result[:is_initiator],
        session_id: session&.session_id,
        video_id: match_result[:video_id],
        video_url: match_result[:video_url],
        video_name: match_result[:video_name]
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
