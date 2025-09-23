# Adapter for gradual migration from PoolMatchingService to OptimizedPoolMatchingService
# Maintains API compatibility while improving performance
#
class PoolMatchingAdapter
  def self.use_optimized_service?
    # Enable via environment variable or feature flag
    return true
  end

  def self.new(user_id)
    if use_optimized_service?
      OptimizedPoolMatchingService.new(user_id)
    else
      PoolMatchingService.new(user_id)
    end
  end

  # For direct instantiation
  def initialize(user_id)
    @service = self.class.use_optimized_service? ?
                 OptimizedPoolMatchingService.new(user_id) :
                 PoolMatchingService.new(user_id)
  end

  # Delegate all methods to the underlying service
  def method_missing(method_name, *args, **kwargs, &block)
    result = @service.send(method_name, *args, **kwargs, &block)

    # Convert OptimizedPoolMatchingService::MatchResult to hash for compatibility
    if result.is_a?(OptimizedPoolMatchingService::MatchResult)
      result.to_h
    else
      result
    end
  end

  def respond_to_missing?(method_name, include_private = false)
    @service.respond_to?(method_name, include_private) || super
  end
end
