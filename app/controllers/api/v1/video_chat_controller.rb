class Api::V1::VideoChatController < ApplicationController
  # Require authentication for video chat
  # before_action :authenticate_user! # Commented out - using JWT authentication from concern

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
    user_id = current_user.id
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
