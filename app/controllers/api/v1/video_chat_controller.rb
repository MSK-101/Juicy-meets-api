class Api::V1::VideoChatController < ApplicationController
  # Require authentication for video chat
  before_action :authenticate_user!, except: [:leave]

  # Using PubNub for signaling - no server-side signal storage needed
  # Include coin deduction service for connection costs

  # POST /api/video_chat/join
  # User joins the video chat queue with real-time notifications
  def join
    user_id = current_user&.id || params[:user_id]
    user = User.find(user_id)
    user.go_online
    current_user = user

    # Clean up any old entries for this user
    VideoWaitingRoom.where(user_id: user_id).destroy_all

    # Get user's pool and sequence information
    pool = user.pool
    sequence = user.role == 'staff' ? user.staff_assignment&.sequence : user.pool&.sequences&.active&.ordered&.first
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

    # Use real-time matching service with instant PubNub notifications
    matching_service = RealtimePoolMatchingService.new(user_id)
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
      render json: { status: 'joined_queue', user_id: user_id, message: match_result[:message], stauts: '200' }
    end
  end

  # GET /api/video_chat/status
  # DEPRECATED: Status polling replaced by real-time PubNub notifications
  # Kept for backward compatibility and fallback scenarios
  def status
    user_id = current_user.id

    # Status endpoint now mainly for fallback - real-time notifications via PubNub

    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    unless waiting_entry
      render json: { status: 'not_in_queue' }
      return
    end

    if waiting_entry.room_id.present?
      # User has been matched - return cached match data

      # Get the user's actual role for proper match_type
      user = User.find(user_id)
      user_match_type = user.role == 'staff' ? 'staff' : 'real_user'

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
        match_type: user_match_type,
        actual_match_type: actual_match_type,
        partner: {
          id: waiting_entry.partner_user_id || 'video',
          type: waiting_entry.match_type
        },
        is_initiator: waiting_entry.is_initiator,
        session_version: waiting_entry.session_version,
        video_id: waiting_entry.video_id,
        video_url: waiting_entry.video_info&.dig(:url),
        video_name: waiting_entry.video_info&.dig(:name)
      }
      return
    end

    # Return waiting status - real-time notifications will handle match updates
    render json: {
      status: 'waiting',
      message: 'Use PubNub notifications for real-time updates'
    }
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
  # User leaves the video chat with instant partner notification
  def leave
    user_id = current_user&.id || params[:user_id]
    notification_service = PubnubNotificationService.new

    # Find and clean up all waiting room entries for this user
    ts = Time.at(params[:ts].to_i / 1000.0)
    waiting_entries = VideoWaitingRoom.where(user_id: user_id, created_at: ..ts)

    waiting_entries.each do |waiting_entry|
      if waiting_entry.room_id.present? && waiting_entry.partner_user_id.present?
        # INSTANT notification to partner that user left
        notification_service.notify_partner_left(waiting_entry.partner_user_id, waiting_entry.room_id)

        # End the current session
        end_current_session(waiting_entry.room_id, user_id)
      end

      # Destroy the waiting entry
      waiting_entry.destroy
    end

    # Also clean up any VideoChatSessions that might be active
    active_sessions = VideoChatSession.where(user_id: user_id, status: 'active')
    active_sessions.update_all(
      status: 'completed',
      ended_at: Time.current
    )

    render json: { status: 'left' }
  end

  # POST /api/video_chat/swipe
  # User swipes to get next match - ULTRA FAST with background jobs
  def swipe
    user_id = current_user.id

    # Ultra-fast: Single query with minimal includes
    waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)

    unless waiting_entry
      render json: { error: 'User not in queue' }, status: :bad_request
      return
    end

    # ULTRA FAST: Move session cleanup to background job
    if waiting_entry.room_id.present?
      SessionCleanupJob.perform_later(waiting_entry.room_id, user_id)
    end

    # ULTRA FAST: Move coin deduction to background job
    CoinDeductionJob.perform_later(user_id, :per_swipe)

    # Use real-time matching service with instant PubNub notifications
    matching_service = RealtimePoolMatchingService.new(user_id)
    match_result = matching_service.find_next_match

    if match_result[:success]
      # ULTRA FAST: Move all heavy operations to background jobs
      # Convert MatchResult to hash for ActiveJob serialization
      match_data = match_result.is_a?(Hash) ? match_result : match_result.to_h
      SessionManagementJob.perform_later(user_id, match_data)
      UserInfoUpdateJob.perform_later(user_id)

      # ULTRA FAST: Return immediately with minimal data (no database queries)
      response_data = build_ultra_fast_match_response(match_result)
      render json: response_data
    else
      # ULTRA FAST: Return waiting status immediately
      render json: build_ultra_fast_waiting_response(match_result)
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

    begin
      # Find all waiting room entries for this room
      waiting_entries = VideoWaitingRoom.where(room_id: room_id)

      if waiting_entries.empty?
        render json: { success: false, message: 'No waiting room entries found' }
        return
      end

      # Update status to 'completed' and add completion timestamp
      waiting_entries.update_all(
        status: 'completed',
        completed_at: Time.current,
        updated_at: Time.current
      )

      render json: {
        success: true,
        message: 'Waiting room cleared successfully',
        room_id: room_id,
        entries_updated: waiting_entries.count
      }
    rescue => e
      render json: {
        success: false,
        error: 'Failed to clear waiting room',
        message: e.message
      }, status: :internal_server_error
    end
  end

  private

  def apply_per_swipe_deduction(user_id)
    # Optimized: Check if user has coins before applying deduction
    user = User.find(user_id)

    if user.coin_balance <= 0
      return {
        success: true,
        deducted: 0,
        new_balance: user.coin_balance,
        error: 'No coins available',
        no_coins: true
      }
    end

    # Find active per-swipe rule
    per_swipe_rule = DeductionRule.active.per_swipe.first

    unless per_swipe_rule
      return {
        success: true,
        deducted: 0,
        new_balance: user.coin_balance,
        error: 'No per-swipe rule configured'
      }
    end

    # Apply the deduction
    result = CoinDeductionService.apply_per_swipe_deduction(user_id, per_swipe_rule)

    if result[:success]
    else
    end

    result
  rescue => e
    { success: false, deducted: 0, new_balance: user&.coin_balance || 0, error: e.message }
  end

  # Optimized version with caching and reduced queries
  def apply_per_swipe_deduction_optimized(user_id)
    # Cache user balance check to avoid repeated queries
    @user_balance ||= User.find(user_id).coin_balance

    if @user_balance <= 0
      return {
        success: true,
        deducted: 0,
        new_balance: @user_balance,
        error: 'No coins available',
        no_coins: true
      }
    end

    # Cache per-swipe rule to avoid repeated queries
    @per_swipe_rule ||= DeductionRule.active.per_swipe.first

    unless @per_swipe_rule
      return {
        success: true,
        deducted: 0,
        new_balance: @user_balance,
        error: 'No per-swipe rule configured'
      }
    end

    # Apply the deduction
    result = CoinDeductionService.apply_per_swipe_deduction(user_id, @per_swipe_rule)

    # Update cached balance if deduction was successful
    if result[:success] && result[:new_balance]
      @user_balance = result[:new_balance]
    end

    result
  rescue => e
    { success: false, deducted: 0, new_balance: @user_balance || 0, error: e.message }
  end

  # Extract response building to reduce code duplication
  def build_match_response(match_result, session, updated_user_info, swipe_deduction_result)
    {
      status: 'matched',
      room_id: match_result[:room_id],
      match_type: match_result[:match_type],
      actual_match_type: match_result[:actual_match_type],
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
      updated_user_info: updated_user_info,
      swipe_deduction: swipe_deduction_result
    }
  end

  def build_waiting_response(match_result, swipe_deduction_result)
    {
      status: 'waiting',
      message: match_result[:message],
      swipe_deduction: swipe_deduction_result
    }
  end

  # Ultra-fast response builders for immediate return
  def build_fast_match_response(match_result, updated_user_info)
    {
      status: 'matched',
      room_id: match_result[:room_id],
      match_type: match_result[:match_type],
      actual_match_type: match_result[:actual_match_type],
      partner: {
        id: match_result[:partner_id] || 'video',
        type: match_result[:match_type]
      },
      is_initiator: match_result[:is_initiator],
      session_version: match_result[:session_version],
      video_id: match_result[:video_id],
      video_url: match_result[:video_url],
      video_name: match_result[:video_name],
      updated_user_info: updated_user_info,
      # Note: session_id will be available after background job completes
      processing: {
        session_creation: 'in_progress',
        coin_deduction: 'in_progress'
      }
    }
  end

  def build_fast_waiting_response(match_result)
    {
      status: 'waiting',
      message: match_result[:message],
      processing: {
        coin_deduction: 'in_progress'
      }
    }
  end

  # Ultra-fast response builders - minimal data, maximum speed
  def build_ultra_fast_match_response(match_result)
    {
      status: 'matched',
      room_id: match_result[:room_id],
      match_type: match_result[:match_type],
      actual_match_type: match_result[:actual_match_type],
      partner: {
        id: match_result[:partner_id] || 'video',
        type: match_result[:match_type]
      },
      is_initiator: match_result[:is_initiator],
      session_version: match_result[:session_version],
      video_id: match_result[:video_id],
      video_url: match_result[:video_url],
      video_name: match_result[:video_name],
      processing: {
        session_creation: 'in_progress',
        coin_deduction: 'in_progress',
        user_info_update: 'in_progress'
      }
    }
  end

  def build_ultra_fast_waiting_response(match_result)
    {
      status: 'waiting',
      message: match_result[:message],
      processing: {
        coin_deduction: 'in_progress'
      }
    }
  end

  def end_current_session(room_id, user_id)
    # Find and end the current session
    session = VideoChatSession.find_by(
      room_id: room_id,
      user_id: user_id,
      status: 'active'
    )

    if session
      session.end_session
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

    # Apply initial connection cost deduction for both users
    begin
      # Deduct 1 coin from current user
      current_deduction = CoinDeductionService.deduct_initial_connection_cost(current_user_id)
      if current_deduction[:success]
      else
      end

      # Deduct 1 coin from partner user
      partner_deduction = CoinDeductionService.deduct_initial_connection_cost(other_waiting.user_id)
      if partner_deduction[:success]
      else
      end
    rescue => e
    end
  end
end
