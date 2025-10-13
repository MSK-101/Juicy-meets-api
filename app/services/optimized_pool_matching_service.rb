# Optimized Pool Matching Service
# Handles video chat matching with proper separation of concerns
#
# MATCHING RULES:
# - Staff users: Only match with real app users, never with other staff or videos
# - App users: Can match with real users → staff → videos (priority order)
# - Videos: Can be used by multiple users simultaneously
#
class OptimizedPoolMatchingService
  include ActiveSupport::Configurable

  # Core matching result structure
  MatchResult = Struct.new(
    :success, :match_type, :actual_match_type, :partner_id, :video_id, :video_url, :video_name,
    :room_id, :session_version, :is_initiator, :reason, :message, keyword_init: true
  ) do
    def to_h
      super.compact
    end
  end

  def initialize(user_id)
    @user_id = user_id

    # Ultra-optimized: Single query with strategic associations
    # Only include what we actually need to avoid over-fetching
    @user = User.includes(
      :staff_assignment,
      :video_waiting_rooms,
      :purchases,  # Needed for pool determination
      staff_assignment: [:pool, :sequence]
    ).find_by(id: user_id)

    return unless @user
    return failure_result('User account suspended') if @user.user_status == 'suspended'

    @pool = @user.pool  # This is a method that determines pool based on coins/staff
    @sequence = find_user_sequence
    @waiting_entry = @user.video_waiting_rooms.first

    # Cache frequently accessed data with optimized queries
    @users_in_sessions = cache_active_session_users_optimized
    @recent_partners = cache_recent_partner_ids_optimized
    @historical_matches = cache_historical_matches_optimized

  end

  # Main matching entry point
  def find_match(max_retries: 3)
    return failure_result('User not found') unless @user
    return failure_result('Pool not assigned') unless @pool
    return failure_result('Sequence not found') unless @sequence

    # Check if user is suspended
    if @user.user_status == 'suspended'
      return failure_result('User account suspended')
    end

    # Try matching with retries
    attempt_matching_with_retries(max_retries)
  end

  # Handle swipe to next match
  def find_next_match
    return failure_result('User not found') unless @user

    cleanup_current_session

    # Increment video count on every swipe attempt (not just successful matches)
    # This ensures users progress through sequences even if no matches are available
    increment_video_count

    check_and_advance_sequence
    find_match
  end

  # Create session tracking
  def create_session(match_data)
    return nil unless match_data[:success]

    session_params = build_session_params(match_data)
    VideoChatSession.create!(session_params)
  end

  # Get user sequence info for frontend
  def get_updated_sequence_info
    return nil unless @user

    @user.reload
    {
      pool_id: @user.pool_id,
      sequence_id: @user.sequence_id,
      videos_watched_in_current_sequence: @user.videos_watched_in_current_sequence || 0,
      sequence_total_videos: @user.sequence_total_videos || 0
    }
  end

  # ============================================================================
  # CORE MATCHING LOGIC
  # ============================================================================

  def attempt_matching_with_retries(max_retries)
    max_retries.times do |attempt|

      match_result = execute_matching_strategy
      return match_result if match_result[:success]

      # Wait and refresh data for retry
      sleep(1) if attempt < max_retries - 1
      refresh_user_data
    end

    staff_no_match_message
  end

  def execute_matching_strategy
    if @user.role == 'staff'
      # Staff only matches with real users
      find_real_user_match
    else
      # App users: try sequence-based matching with content priorities
      find_match_with_sequence_advancement
    end
  end

  def find_match_with_sequence_advancement(max_attempts: 10)
    visited_sequences = Set.new

    max_attempts.times do |attempt|

      # Check for infinite loop
      if visited_sequences.include?(@sequence&.id)
        break
      end

      visited_sequences.add(@sequence&.id)

      # Try current sequence content types in order
      match_result = try_sequence_content_types
      if match_result[:success]
        return match_result
      end

      # If no match found, advance to next sequence
      unless advance_to_next_sequence
        break
      end
    end

    failure_result('No matches available after checking all sequences')
  end

  def try_sequence_content_types
    @sequence.content_type.each do |content_type|

      # Try without repeats first, then with repeats
      [false, true].each do |allow_repeats|
        match_result = match_by_content_type(content_type, allow_repeats)
        return match_result if match_result[:success]
      end
    end

    failure_result("No matches in sequence #{@sequence.name}")
  end

  def match_by_content_type(content_type, allow_repeats)
    case content_type
    when 'app_users'
      find_real_user_match(allow_repeats: allow_repeats)
    when 'staff'
      find_staff_match(allow_repeats: allow_repeats)
    when 'recorded_videos'
      find_video_match(allow_repeats: allow_repeats)
    else
      failure_result("Unknown content type: #{content_type}")
    end
  end

  # ============================================================================
  # SPECIFIC MATCH TYPES
  # ============================================================================

  def find_real_user_match(allow_repeats: false)

    base_query = build_real_user_query(allow_repeats)
    user_match = find_user_with_gender_preference(base_query)
    return failure_result('No real users available') unless user_match

    create_user_to_user_match(user_match)
  end

  def find_staff_match(allow_repeats: false)
    return failure_result('Staff cannot match with staff') if @user.role == 'staff'

    base_query = build_staff_query(allow_repeats)
    staff_match = find_user_with_gender_preference(base_query)
    return failure_result('No staff available') unless staff_match

    create_user_to_staff_match(staff_match)
  end

  def find_video_match(allow_repeats: false)
    return failure_result('Staff users do not watch videos') if @user.role == 'staff'

    # Only check if videos should be shown when content type is not specifically 'recorded_videos'
    # When sequence content type is 'recorded_videos', we must respect that and show videos
    unless @sequence.content_type.include?('recorded_videos')
      return failure_result('Users/staff available, no video needed') unless should_show_video?
    end

    video = if allow_repeats
      get_video_with_rotation
    else
      get_unwatched_video
    end

    return failure_result('No videos available') unless video

    create_video_match(video)
  end

  # ============================================================================
  # QUERY BUILDERS
  # ============================================================================

  def build_real_user_query(allow_repeats)
    # ULTRA-OPTIMIZED: Use raw SQL for fastest possible query
    base_query = base_user_query.where(match_type: 'real_user')

    # CRITICAL: Exclude blocked users from matching
    base_query = exclude_blocked_users(base_query)

    if allow_repeats
      # When allowing repeats, use deterministic prioritization
      # This returns an array, not a query
      return prioritize_oldest_matches(base_query, 'real_user')
    else
      # Exclude recent partners completely
      query = base_query
      query = query.where.not(users: { id: @recent_partners }) unless @recent_partners.empty?
      return query.order(:joined_at)
    end
  end

  def build_staff_query(allow_repeats)
    # Optimized staff query with proper index utilization
    base_query = VideoWaitingRoom.joins(:user)
                                .where(
                                  match_type: 'staff',
                                  status: 'waiting',
                                  pool_id: @pool.id,
                                  sequence_id: @sequence.id,
                                  room_id: nil,
                                  session_version: nil
                                )
                                .where.not(user_id: @user_id)

    # Apply exclusions only if we have data to exclude
    base_query = base_query.where.not(users: { id: @users_in_sessions }) if @users_in_sessions.any?

    # CRITICAL: Exclude blocked users from matching
    base_query = exclude_blocked_users(base_query)

    if allow_repeats
      # When allowing repeats with staff, use deterministic prioritization
      # This returns an array, not a query
      return prioritize_oldest_matches(base_query, 'staff')
    else
      # Exclude recent partners completely
      query = base_query
      query = query.where.not(users: { id: @recent_partners }) if @recent_partners.any?
      return query.order(:joined_at)
    end
  end

  def base_user_query
    # Optimized: Structure query for best index usage
    # Assumes composite index on (pool_id, sequence_id, status, room_id)
    query = VideoWaitingRoom.joins(:user)
                           .where(
                             pool_id: @pool.id,
                             sequence_id: @sequence.id,
                             status: 'waiting',
                             room_id: nil,
                             session_version: nil
                           )
                           .where.not(user_id: @user_id)

    # Apply exclusions only if we have data to exclude (avoid empty array queries)
    query = query.where.not(users: { id: @users_in_sessions }) if @users_in_sessions.any?

    query
  end

  # CRITICAL: Exclude users that the current user has blocked
  def exclude_blocked_users(query)
    return query unless @user&.blocked_users&.any?

    # Convert blocked user IDs to integers for proper comparison
    blocked_user_ids = @user.blocked_users.map(&:to_i).compact
    return query if blocked_user_ids.empty?

    # Exclude blocked users from the query
    query.where.not(users: { id: blocked_user_ids })
  end

  # Ultra-optimized: Cache frequently accessed data with minimal queries
  def cache_active_session_users_optimized
    # Single optimized query - only fetch what we need
    VideoWaitingRoom.where(status: 'matched')
                   .where.not(room_id: nil)
                   .pluck(:user_id)
  end

  def cache_recent_partner_ids_optimized
    # Extended time window to better avoid repeats (30 minutes vs 10 minutes in original)
    # Optimized: Use index-friendly query with specific columns
    VideoChatSession.where(
      user_id: @user_id,
      created_at: 30.minutes.ago..Time.current,
      status: ['active', 'completed']
    ).where.not(partner_user_id: nil)
     .pluck(:partner_user_id)
  end

  def cache_historical_matches_optimized
    # Pre-fetch all historical matches to avoid repeated queries
    # This is used by prioritize_oldest_matches
    VideoChatSession.where(
      user_id: @user_id,
      status: ['active', 'completed']
    ).where.not(partner_user_id: nil)
     .group(:partner_user_id)
     .minimum(:created_at)
  end

  # Prioritize users based on oldest match when repeats are allowed - DETERMINISTIC & OPTIMIZED
  def prioritize_oldest_matches(query, match_type)
    # Fetch all available users into memory for deterministic processing
    available_users = query.to_a

    return [] if available_users.empty?

    # Use pre-cached historical matches - no additional database query!
    all_previous_matches = @historical_matches

    # Step 1: Find users we've never matched with
    never_matched_users = available_users.select { |user_entry|
      !all_previous_matches.key?(user_entry.user_id)
    }

    if never_matched_users.any?
      # Sort by join time for deterministic ordering
      return never_matched_users.sort_by(&:joined_at)
    end

    # Step 2: All are repeats - sort by oldest match time (most fair)

    repeated_users_with_times = available_users.map do |user_entry|
      oldest_match_time = all_previous_matches[user_entry.user_id]
      {
        user_entry: user_entry,
        oldest_match_time: oldest_match_time || Time.current, # Fallback for safety
        user_id: user_entry.user_id
      }
    end

    # Sort by oldest match time first (fairest), then by join time for tie-breaking
    sorted_users = repeated_users_with_times.sort_by do |item|
      [item[:oldest_match_time], item[:user_entry].joined_at]
    end

    result_users = sorted_users.map { |item| item[:user_entry] }

    # Enhanced logging for debugging
    sorted_info = sorted_users.map do |item|
      time_ago = ((Time.current - item[:oldest_match_time]) / 1.hour).round(1)
      "user_#{item[:user_id]}(#{time_ago}h_ago)"
    end

    result_users
  end

  # ============================================================================
  # GENDER PREFERENCE MATCHING
  # ============================================================================

  def find_user_with_gender_preference(base_query_or_array)
    # Handle both ActiveRecord::Relation and Array inputs
    if base_query_or_array.is_a?(Array)
      return find_user_with_gender_preference_from_array(base_query_or_array)
    end

    # Handle ActiveRecord::Relation (original logic)
    if @user.interested_in.present? && @user.interested_in != 'other' && @pool.name == 'Pool K'
      preferred_query = base_query_or_array.where(users: { gender: @user.interested_in })
      preferred_match = preferred_query.first
      return preferred_match if preferred_match

      # Try same gender as fallback
      same_gender_query = base_query_or_array.where(users: { gender: @user.gender })
      same_gender_match = same_gender_query.first
      return same_gender_match if same_gender_match
    end

    # No gender preference or other pools - return first available
    base_query_or_array.first
  end

  # Handle gender preference selection from pre-sorted array
  # IMPORTANT: This maintains the priority order (no repeats first, then oldest repeats)
  # while applying gender preferences within each priority group
  def find_user_with_gender_preference_from_array(users_array)
    return nil if users_array.empty?

    # Try preferred gender first (Pool K only)
    if @user.interested_in.present? && @user.interested_in != 'other' && @pool.name == 'Pool K'

      # Find the FIRST user of preferred gender in priority order
      # This respects: never-matched users first, then oldest repeats
      preferred_match = users_array.find { |user_entry| user_entry.user.gender == @user.interested_in }

      if preferred_match
        return preferred_match
      end

      # Try same gender as fallback - also respects priority order
      same_gender_match = users_array.find { |user_entry| user_entry.user.gender == @user.gender }

      if same_gender_match
        return same_gender_match
      end

    end

    # No gender preference or other pools - return first in priority order
    selected_user = users_array.first
    selected_user
  end

  # ============================================================================
  # MATCH CREATION
  # ============================================================================

  def create_user_to_user_match(other_user)
    ActiveRecord::Base.transaction do
      room_data = create_room_and_session_data
      update_waiting_entries(other_user, room_data, 'real_user')
      # Video count already incremented in find_next_match

      success_result(
        match_type: 'real_user',
        actual_match_type: 'real_user',
        partner_id: other_user.user_id,
        room_id: room_data[:room_id],
        session_version: room_data[:session_version],
        is_initiator: @user_id < other_user.user_id
      )
    end
  rescue => e
    failure_result('Failed to create match')
  end

  def create_user_to_staff_match(staff_entry)
    ActiveRecord::Base.transaction do
      staff_entry.reload.lock!

      room_data = create_room_and_session_data
      update_waiting_entries(staff_entry, room_data, 'staff')
      # Video count already incremented in find_next_match

      success_result(
        match_type: 'staff',
        actual_match_type: 'staff',
        partner_id: staff_entry.user_id,
        room_id: room_data[:room_id],
        session_version: room_data[:session_version],
        is_initiator: @user_id < staff_entry.user_id
      )
    end
  rescue => e
    failure_result('Staff no longer available')
  end

  def create_video_match(video)
    room_data = create_room_and_session_data

    @waiting_entry.update!(
      room_id: room_data[:room_id],
      session_version: room_data[:session_version],
      status: 'matched',
      match_type: 'video',
      video_id: video.id,
      is_initiator: true
    )

    # Video count already incremented in find_next_match

    success_result(
      match_type: 'video',
      actual_match_type: 'video',
      video_id: video.id,
      video_url: video.video_file.attached? ? video.video_file.url : nil,
      video_name: video.name,
      room_id: room_data[:room_id],
      session_version: room_data[:session_version],
      is_initiator: true
    )
  end

  # ============================================================================
  # SESSION AND ROOM MANAGEMENT
  # ============================================================================

  def create_room_and_session_data
    room_id = "room_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
    session_version = "version_#{Time.current.to_i}_#{SecureRandom.hex(4)}"

    { room_id: room_id, session_version: session_version }
  end

  def update_waiting_entries(partner_entry, room_data, match_type)
    is_initiator = @user_id < partner_entry.user_id

    # Update current user
    @waiting_entry.update!(
      room_id: room_data[:room_id],
      partner_user_id: partner_entry.user_id,
      status: 'matched',
      match_type: match_type,
      session_version: room_data[:session_version],
      is_initiator: is_initiator
    )

    # Update partner
    partner_entry.update!(
      room_id: room_data[:room_id],
      partner_user_id: @user_id,
      status: 'matched',
      match_type: match_type,
      session_version: room_data[:session_version],
      is_initiator: !is_initiator
    )
  end

  def cleanup_current_session
    return unless @waiting_entry&.room_id.present?

    room_id = @waiting_entry.room_id

    # Disconnect all users in the room
    VideoWaitingRoom.where(room_id: room_id).find_each do |entry|
      reset_waiting_entry(entry)
      trigger_new_match_for_user(entry.user_id) unless entry.user_id == @user_id
    end
  end

  def reset_waiting_entry(entry)
    entry.update!(
      room_id: nil,
      partner_user_id: nil,
      status: 'waiting',
      session_version: nil,
      video_id: nil,
      updated_at: Time.current
    )
  end

  # ============================================================================
  # SEQUENCE MANAGEMENT
  # ============================================================================

  def find_user_sequence
    return nil unless @user && @pool

    # If user is staff, they should have a fixed sequence from staff_assignment
    if @user.role == 'staff'
      return @user.staff_assignment&.sequence
    end

    # For app users, determine sequence based on their current state
    if @user.sequence_id.present?
      # User has a sequence_id, find that sequence
      sequence = @pool.sequences.active.find_by(id: @user.sequence_id)
      if sequence

        # Ensure user has sequence_total_videos set
        if @user.sequence_total_videos.nil?
          @user.update!(sequence_total_videos: sequence.video_count)
        end

        return sequence
      else
      end
    end

    # If no valid sequence_id, assign the first sequence in the pool
    first_sequence = @pool.sequences.active.ordered.first
    if first_sequence

      # Update user's sequence info in database
      update_user_sequence(first_sequence, reset_count: true)

      return first_sequence
    else
      return nil
    end
  end

  def advance_to_next_sequence
    return false unless @user && @pool

    # Find next sequence in the pool
    next_sequence = find_next_sequence_in_pool

    if next_sequence
      # Update user's sequence and reset video count
      update_user_sequence(next_sequence, reset_count: true)
      @sequence = next_sequence  # Update instance variable
      return true
    else
      # No more sequences, wrap back to first sequence
      first_sequence = @pool.sequences.active.ordered.first
      if first_sequence
        update_user_sequence(first_sequence, reset_count: true)
        @sequence = first_sequence  # Update instance variable
        return true
      else
        return false
      end
    end
  end

  def find_next_sequence_in_pool
    return nil unless @pool && @sequence

    # Get all active sequences in the pool, ordered by position
    active_sequences = @pool.sequences.active.ordered

    # Find current sequence position
    current_position = @sequence.position

    # Find next sequence
    # NOTE:
    # Previously this required the next sequence to have active videos, which caused
    # users to get stuck on a video-focused sequence (e.g., recorded_videos with count 1)
    # if the subsequent sequence did not have videos (e.g., app_users, staff).
    #
    # Correct behavior:
    # - If the next sequence includes 'recorded_videos', require it to have active videos
    # - Otherwise, allow advancing regardless of videos being present
    next_sequence = active_sequences.find do |seq|
      seq.position > current_position && (
        !seq.content_type.include?('recorded_videos') || seq.videos.active.any?
      )
    end

    if next_sequence
      next_sequence
    else
      nil
    end
  end

  def check_and_advance_sequence
    return unless @user && @sequence

    # Get current video count from user
    current_video_count = @user.videos_watched_in_current_sequence || 0

    # Check if sequence should advance
    if current_video_count >= @sequence.video_count
      advance_to_next_sequence
    else
    end
  end

  def update_user_sequence(sequence, reset_count: false)
    update_params = {
      sequence_id: sequence.id,
      sequence_total_videos: sequence.video_count
    }
    update_params[:videos_watched_in_current_sequence] = 0 if reset_count

    @user.update!(update_params)
  end

  def increment_video_count
    return unless @user && @sequence

    # Get current video count from user
    current_video_count = @user.videos_watched_in_current_sequence || 0
    new_video_count = current_video_count + 1

    # Update user's video count
    @user.update!(videos_watched_in_current_sequence: new_video_count)

  end

  # ============================================================================
  # VIDEO MANAGEMENT
  # ============================================================================

  def should_show_video?
    @sequence.videos.active.exists?
  end

  def get_unwatched_video
    watched_ids = @user.watched_video_ids_in_sequence(@sequence.id)
    @sequence.videos.active.where.not(id: watched_ids).order(:created_at).first
  end

  def get_video_with_rotation
    # First try unwatched
    unwatched = get_unwatched_video
    return unwatched if unwatched

    # If all watched, rotate to avoid consecutive repeats
    all_videos = @sequence.videos.active.order(:created_at)
    return all_videos.first if all_videos.size <= 1

    # Get all videos with their last match times
    video_match_times = get_video_match_times

    # Find the video with the oldest match time (least recently watched)
    oldest_video = find_video_with_oldest_match(all_videos, video_match_times)

    # Debug logging for video rotation
    if oldest_video
      last_match_time = video_match_times[oldest_video.id]
      time_ago = last_match_time ? ((Time.current - last_match_time) / 1.minute).round(1) : "never"
      Rails.logger.info "Video rotation: Selected video #{oldest_video.id} (#{oldest_video.name}) - last watched #{time_ago} minutes ago"
    end

    oldest_video || all_videos.first
  end

  # Get the last match time for each video in this sequence
  def get_video_match_times
    @user.video_chat_sessions
         .where(sequence_id: @sequence.id)
         .where.not(video_id: nil)
         .group(:video_id)
         .maximum(:created_at)
  end

  # Find the video that was watched least recently (oldest match time)
  def find_video_with_oldest_match(all_videos, video_match_times)
    return all_videos.first if video_match_times.empty?

    # Create array of videos with their match times
    videos_with_times = all_videos.map do |video|
      last_match_time = video_match_times[video.id]
      {
        video: video,
        last_match_time: last_match_time || Time.at(0), # Never watched = oldest possible time
        video_id: video.id
      }
    end

    # Sort by last match time (oldest first), then by video creation time for tie-breaking
    sorted_videos = videos_with_times.sort_by do |item|
      [item[:last_match_time], item[:video].created_at]
    end

    # Return the video with the oldest match time
    sorted_videos.first[:video]
  end

  # ============================================================================
  # SESSION TRACKING
  # ============================================================================

  def build_session_params(match_data)
    session_type = case match_data[:match_type]
                  when 'real_user' then 'user_to_user'
                  when 'staff' then 'user_to_staff'
                  when 'video' then 'user_to_video'
                  else 'user_to_user'
                  end

    {
      user_id: @user_id,
      pool_id: @pool&.id,
      sequence_id: @sequence&.id,
      session_id: "session_#{Time.current.to_i}_#{SecureRandom.hex(4)}",
      started_at: Time.current,
      session_type: session_type,
      partner_user_id: match_data[:partner_id],
      video_id: match_data[:video_id],
      room_id: match_data[:room_id],
      status: 'active'
    }
  end

  # ============================================================================
  # HELPER METHODS
  # ============================================================================

  def watching_video?
    @waiting_entry&.match_type == 'video' && @waiting_entry&.room_id.present?
  end

  def handle_video_swipe
    # Respect sequence content type priority even when swiping from video
    if @sequence.content_type.include?('recorded_videos')
      # If sequence is video-focused, try video first, then fallback to others
      video_match = find_video_match(allow_repeats: true)
      return video_match if video_match[:success]
      return find_real_user_match if find_real_user_match[:success]
      return find_staff_match if find_staff_match[:success]
    else
      # Original priority: real users → staff → videos
      return find_real_user_match if find_real_user_match[:success]
      return find_staff_match if find_staff_match[:success]
      video_match = find_video_match(allow_repeats: true)
      return video_match if video_match[:success]
    end

    failure_result('No matches available')
  end

  # Use cached data instead of querying every time
  def users_in_active_sessions
    @users_in_sessions
  end

  def refresh_user_data
    @user.reload
    if @waiting_entry
      @waiting_entry = VideoWaitingRoom.find_by(id: @waiting_entry.id)
    end
  end

  def staff_no_match_message
    if @user.role == 'staff'
      failure_result('Staff users wait for real app users only - none currently available')
    else
      failure_result('No matches available after retries')
    end
  end

  def trigger_new_match_for_user(user_id)

    new_service = self.class.new(user_id)
    match_result = new_service.find_match

    if match_result[:success]
      new_service.create_session(match_result)
    end
  rescue => e
  end

  # ============================================================================
  # RESULT BUILDERS
  # ============================================================================

  def success_result(**options)
    MatchResult.new(success: true, **options)
  end

  def failure_result(reason)
    MatchResult.new(success: false, reason: reason, message: reason)
  end
end
