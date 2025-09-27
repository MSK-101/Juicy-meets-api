# PubNub Notification Service for Real-time Match Notifications
# Eliminates frontend polling by pushing match events instantly
class PubnubNotificationService
  include ActiveSupport::Configurable

  # Initialize PubNub client with environment credentials
  def initialize
    @pubnub = PubNubGlobal.instance || create_fallback_client
  end

  def create_fallback_client
    Pubnub.new(
      publish_key: ENV['PUBNUB_PUBLISH_KEY'],
      subscribe_key: ENV['PUBNUB_SUBSCRIBE_KEY'],
      uuid: "server-#{Rails.env}-#{Time.current.to_i}"
    )
  end

  # Async publish helper for non-blocking notifications
  def publish_async(channel, message, &block)
    Thread.new do
      begin
        @pubnub.publish(
          channel: channel,
          message: message,
          store: false,
          replicate: true
        ) do |envelope|
          if envelope.error?
            block.call(false, envelope.error_message) if block_given?
          else
            block.call(true, nil) if block_given?
          end
        end
      rescue => e
        block.call(false, e.message) if block_given?
      end
    end
  end

  # Notify user of successful match - INSTANT notification
  def notify_match_found(user_id, match_data)
    channel = "user.#{user_id}.matches"

    notification = {
      type: 'match_found',
      timestamp: Time.current.to_i,
      data: {
        status: 'matched',
        room_id: match_data[:room_id],
        match_type: match_data[:match_type],
        actual_match_type: match_data[:actual_match_type],
        partner: {
          id: match_data[:partner_id] || 'video',
          type: match_data[:match_type]
        },
        is_initiator: match_data[:is_initiator],
        session_version: match_data[:session_version],
        video_id: match_data[:video_id],
        video_url: match_data[:video_url],
        video_name: match_data[:video_name]
      }
    }

    # Publish asynchronously with guaranteed delivery
    publish_async(channel, notification) do |success, error|
      if error
        Rails.logger.error "PubNub notification failed for user #{user_id}: #{error}"
      else
        Rails.logger.info "Match notification sent to user #{user_id} via PubNub"
      end
    end
  end

  # Notify user when they're added to queue - for UI feedback
  def notify_queue_joined(user_id, queue_position = nil)
    channel = "user.#{user_id}.matches"

    notification = {
      type: 'queue_joined',
      timestamp: Time.current.to_i,
      data: {
        status: 'waiting',
        queue_position: queue_position,
        estimated_wait_time: calculate_estimated_wait_time(queue_position)
      }
    }

    @pubnub.publish(
      channel: channel,
      message: notification,
      store: false
    )
  end

  # Notify user of match failure - for immediate retry
  def notify_match_failed(user_id, reason)
    channel = "user.#{user_id}.matches"

    notification = {
      type: 'match_failed',
      timestamp: Time.current.to_i,
      data: {
        status: 'no_match',
        reason: reason,
        retry_suggested: true
      }
    }

    @pubnub.publish(
      channel: channel,
      message: notification,
      store: false
    )
  end

  # Notify partner when user leaves - for instant cleanup
  def notify_partner_left(partner_id, room_id)
    return unless partner_id && partner_id != 'video'

    channel = "user.#{partner_id}.matches"

    notification = {
      type: 'partner_left',
      timestamp: Time.current.to_i,
      data: {
        room_id: room_id,
        action: 'find_new_match'
      }
    }

    @pubnub.publish(
      channel: channel,
      message: notification,
      store: false
    )
  end

  # Batch notify multiple users - for efficient staff notifications
  def batch_notify_matches(match_pairs)
    return if match_pairs.empty?

    # Group notifications by channel for efficiency
    notifications_by_channel = {}

    match_pairs.each do |user_id, match_data|
      channel = "user.#{user_id}.matches"
      notifications_by_channel[channel] ||= []

      notification = {
        type: 'match_found',
        timestamp: Time.current.to_i,
        data: build_match_notification_data(match_data)
      }

      notifications_by_channel[channel] << notification
    end

    # Send all notifications in parallel
    notifications_by_channel.each do |channel, notifications|
      notifications.each do |notification|
        @pubnub.publish(
          channel: channel,
          message: notification,
          store: false
        )
      end
    end
  end

  # Subscribe to user events for real-time processing
  def subscribe_to_user_events(user_id, &block)
    channel = "user.#{user_id}.events"

    @pubnub.subscribe(
      channels: [channel],
      heartbeat: 30
    ) do |envelope|
      if envelope.error?
        Rails.logger.error "PubNub subscription error for user #{user_id}: #{envelope.error_message}"
      else
        block.call(envelope.message) if block_given?
      end
    end
  end

  # Health check for PubNub connectivity
  def health_check
    start_time = Time.current

    @pubnub.time do |envelope|
      if envelope.error?
        {
          status: 'error',
          latency: nil,
          error: envelope.error_message
        }
      else
        {
          status: 'healthy',
          latency: ((Time.current - start_time) * 1000).round(2), # ms
          server_time: envelope.result[:data][:timetoken]
        }
      end
    end
  end

  private

  def build_match_notification_data(match_data)
    {
      status: 'matched',
      room_id: match_data[:room_id],
      match_type: match_data[:match_type],
      actual_match_type: match_data[:actual_match_type],
      partner: {
        id: match_data[:partner_id] || 'video',
        type: match_data[:match_type]
      },
      is_initiator: match_data[:is_initiator],
      session_version: match_data[:session_version],
      video_id: match_data[:video_id],
      video_url: match_data[:video_url],
      video_name: match_data[:video_name]
    }
  end

  def calculate_estimated_wait_time(queue_position)
    return 30 unless queue_position # Default 30 seconds if unknown

    # Estimate based on average match time (can be refined with analytics)
    base_wait_time = 15 # seconds per position
    (queue_position * base_wait_time).clamp(5, 300) # 5s min, 5min max
  end

end
