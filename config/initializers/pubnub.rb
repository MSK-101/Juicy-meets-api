# PubNub Configuration for Real-time Video Chat Notifications
# Enables instant match notifications and eliminates polling overhead

Rails.application.configure do
  # Ensure PubNub credentials are available
  if ENV['PUBNUB_PUBLISH_KEY'].blank? || ENV['PUBNUB_SUBSCRIBE_KEY'].blank?
    Rails.logger.warn "PubNub credentials not configured. Real-time notifications will be disabled."
  else
    Rails.logger.info "PubNub configured successfully for real-time notifications"
  end
end

# Global PubNub service instance for performance
class PubNubGlobal
  @instance = nil
  @mutex = Mutex.new

  def self.instance
    return @instance if @instance

    @mutex.synchronize do
      return @instance if @instance

      if ENV['PUBNUB_PUBLISH_KEY'].present? && ENV['PUBNUB_SUBSCRIBE_KEY'].present?
        @instance = Pubnub.new(
          publish_key: ENV['PUBNUB_PUBLISH_KEY'],
          subscribe_key: ENV['PUBNUB_SUBSCRIBE_KEY'],
          uuid: "server-#{Rails.env}-#{SecureRandom.hex(4)}",
          origin: 'ps.pndsn.com', # Use fastest endpoint
          heartbeat_interval: 30,
          subscribe_timeout: 310,
          non_subscribe_timeout: 10,
          connect_timeout: 5,
          ssl: true
        )

        Rails.logger.info "Global PubNub instance created"
      else
        Rails.logger.warn "PubNub not configured - real-time features disabled"
      end
    end

    @instance
  end

  def self.configured?
    ENV['PUBNUB_PUBLISH_KEY'].present? && ENV['PUBNUB_SUBSCRIBE_KEY'].present?
  end
end
