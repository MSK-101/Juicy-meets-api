# Real-time Pool Matching Service with PubNub Integration
# Provides instant match notifications and eliminates polling overhead
class RealtimePoolMatchingService < OptimizedPoolMatchingService

  def initialize(user_id)
    super(user_id)
    @notification_service = PubnubNotificationService.new
  end

  # Enhanced find_match with instant notifications
  def find_match(max_retries: 3)
    return failure_result('User not found') unless @user
    return failure_result('Pool not assigned') unless @pool
    return failure_result('Sequence not found') unless @sequence

    # Notify user they're in queue
    @notification_service.notify_queue_joined(@user_id)

    # Try matching with retries (keep original logic)
    match_result = attempt_matching_with_retries(max_retries)

    if match_result[:success]
      # INSTANT notification to user
      @notification_service.notify_match_found(@user_id, match_result.to_h)

      # If it's a live match, also notify the partner
      if match_result[:partner_id] && match_result[:partner_id] != 'video'
        @notification_service.notify_match_found(match_result[:partner_id], {
          room_id: match_result[:room_id],
          match_type: determine_partner_match_type(match_result[:partner_id]),
          actual_match_type: match_result[:actual_match_type],
          partner_id: @user_id,
          is_initiator: !match_result[:is_initiator],
          session_version: match_result[:session_version]
        })
      end
    else
      # Notify user of match failure for immediate retry
      @notification_service.notify_match_failed(@user_id, match_result[:reason])
    end

    match_result
  end

  # Enhanced swipe with instant cleanup notifications
  def find_next_match
    # Store current partner for cleanup notification
    current_partner_id = @waiting_entry&.partner_user_id
    current_room_id = @waiting_entry&.room_id

    # Perform the swipe
    result = super

    # Notify partner immediately if they were in a live connection
    if current_partner_id && current_partner_id != 'video' && current_room_id
      @notification_service.notify_partner_left(current_partner_id, current_room_id)
    end

    # If new match found, send instant notification
    if result[:success]
      @notification_service.notify_match_found(@user_id, result.to_h)

      # Notify partner if it's a live match
      if result[:partner_id] && result[:partner_id] != 'video'
        @notification_service.notify_match_found(result[:partner_id], {
          room_id: result[:room_id],
          match_type: determine_partner_match_type(result[:partner_id]),
          actual_match_type: result[:actual_match_type],
          partner_id: @user_id,
          is_initiator: !result[:is_initiator],
          session_version: result[:session_version]
        })
      end
    else
      # Re-queue user for matching and notify
      @notification_service.notify_queue_joined(@user_id)
    end

    result
  end

  # Batch matching for high-performance scenarios
  def self.batch_find_matches(user_ids, max_batch_size: 10)
    return [] if user_ids.empty?

    matches = []
    user_ids.each_slice(max_batch_size) do |batch|
      batch_matches = process_batch_matches(batch)
      matches.concat(batch_matches)
    end

    # Send all notifications in one batch
    notification_service = PubnubNotificationService.new
    notification_service.batch_notify_matches(matches.to_h)

    matches
  end

  # Pre-warm WebRTC connections for faster connection times
  def prepare_webrtc_connection(partner_id)
    return unless partner_id && partner_id != 'video'

    # Send pre-connection signal via PubNub to start ICE gathering
    channel = "vc.#{@waiting_entry.room_id}"

    @notification_service.instance_variable_get(:@pubnub).publish(
      channel: channel,
      message: {
        type: 'prepare_connection',
        from: @user_id.to_s,
        to: partner_id.to_s,
        session_version: @waiting_entry.session_version,
        timestamp: Time.current.to_i
      },
      store: false
    )
  end


  def determine_partner_match_type(partner_id)
    partner = User.find_by(id: partner_id)
    return 'unknown' unless partner

    partner.role == 'staff' ? 'staff' : 'real_user'
  end

  def self.process_batch_matches(user_ids)
    matches = []

    user_ids.each do |user_id|
      service = new(user_id)
      match_result = service.find_match(max_retries: 1) # Reduced retries for batch

      if match_result[:success]
        matches << [user_id, match_result.to_h]
      end
    end

    matches
  end

  # Override parent methods to add notifications
  def create_user_to_user_match(other_user)
    result = super(other_user)

    if result[:success]
      # Pre-warm WebRTC connection
      prepare_webrtc_connection(result[:partner_id])
    end

    result
  end

  def create_user_to_staff_match(staff_entry)
    result = super(staff_entry)

    if result[:success]
      # Pre-warm WebRTC connection
      prepare_webrtc_connection(result[:partner_id])
    end

    result
  end

  # Enhanced session cleanup with notifications
  def cleanup_current_session
    current_partner_id = @waiting_entry&.partner_user_id
    current_room_id = @waiting_entry&.room_id

    super

    # Notify partner of cleanup
    if current_partner_id && current_partner_id != 'video' && current_room_id
      @notification_service.notify_partner_left(current_partner_id, current_room_id)
    end
  end
end
