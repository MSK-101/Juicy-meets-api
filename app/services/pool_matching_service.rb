class PoolMatchingService
  include ActiveSupport::Configurable
  require 'set'
  require 'digest'

  # ============================================================================
  # MATCHING RULES:
  # ============================================================================
  #
  # STAFF USERS:
  # - Can ONLY match with REAL APP USERS (never with other staff or videos)
  # - Must wait in queue until real app users are available
  # - Cannot progress through sequences (fixed assignment)
  #
  # APP USERS:
  # - Can match with: REAL APP USERS → STAFF → VIDEOS (in priority order)
  # - Progress through sequences based on video count
  # - Can watch videos when no real users or staff available
  #
  # VIDEOS:
  # - Can be in multiple sessions simultaneously
  # - Only shown to app users, never to staff
  #
  # ============================================================================

  def initialize(user_id)
    @user_id = user_id
    @user = User.find_by(id: user_id)
    @pool = @user&.pool
    @sequence = @user&.staff_assignment&.sequence || find_sequence_for_user
    @waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)
  end

  # Main matching method - tries to find the best match with proper priority order
  def find_match(max_retries = 3)

    # Add specific logging for staff users
    if @user.role == 'staff'
    end

    # Check if current user is currently watching a video
    if @waiting_entry&.match_type == 'video' && @waiting_entry&.room_id.present?
      return handle_video_user_swipe
    end

    attempt = 0
    while attempt < max_retries
      attempt += 1

      # Use the new structured matching approach with proper priority
      match_result = find_match_with_priority_order

      if match_result[:success]
        return match_result
      end

      # If we get here, no match was found
      if attempt < max_retries
        sleep(2) # Wait before retry

        # Refresh user data for next attempt
        @user.reload
        @waiting_entry.reload if @waiting_entry
      end
    end

    # Special message for staff users who couldn't find a match
    if @user.role == 'staff'
      return { success: false, reason: 'Staff users wait for real app users only - no real app users currently available' }
    end

    { success: false, reason: 'No matches available after retries' }
  end

  # NEW: Content-based matching with sequence advancement
  def find_match_with_priority_order

    # For app users, try content-based matching with sequence advancement
    if @user.role != 'staff'
      return find_match_with_sequence_advancement
    end

    { success: false, reason: 'No matches available in any sequence' }
  end

  # Find match with automatic sequence advancement and infinite loop protection
  def find_match_with_sequence_advancement(max_sequence_attempts = 10)

    initial_sequence_id = @sequence&.id
    sequence_attempts = 0
    visited_sequences = Set.new

    while sequence_attempts < max_sequence_attempts
      sequence_attempts += 1

      # Check for infinite loop: if we've seen this sequence before, break
      if visited_sequences.include?(@sequence&.id)
        break
      end

      # Mark this sequence as visited
      visited_sequences.add(@sequence&.id)

      # Try to find match in current sequence
      match_result = find_next_match_by_content_type
      if match_result[:success]
        return match_result
      end

      # If no match found, advance to next sequence
      if advance_to_next_sequence
      else
        break
      end
    end

    { success: false, reason: 'No matches available after checking all sequences' }
  end

  # Find next match when user swipes or disconnects
  def find_next_match_by_content_type
    @sequence.content_type.each do |content_type|

      # Try no-repeat matching first
      match_result = case content_type
      when 'app_users'
        find_real_user_match_no_repeats
      when 'staff'
        find_staff_match_no_repeats
      when 'recorded_videos'
        find_video_match_no_repeats
      end

      return match_result if match_result[:success]

      # If no-repeat failed, try with repeats
      match_result = case content_type
      when 'app_users'
        find_real_user_match_with_repeats
      when 'staff'
        find_staff_match_with_repeats
      when 'recorded_videos'
        find_video_match_with_repeats
      end

      return match_result if match_result[:success]
    end

    # If no matches found for any content type
    { success: false, reason: 'No matches available for current content types' }
  end

  def find_next_match
    return { error: 'User not found' } unless @user

    # First, handle disconnection of both users if they were in a room together
    handle_room_disconnection

    # Check and advance sequence BEFORE finding next match
    # This ensures we're looking for matches in the correct sequence
    check_and_advance_sequence_if_needed

    # Try to find next match with better error handling
    match_result = find_match

    # If no real user match found, provide better fallback logic
    if !match_result[:success] && @user.role != 'staff'

      # Try staff match as fallback
      staff_match = find_staff_match
      if staff_match[:success]
        return staff_match
      end

      # Try video match as final fallback
      video_match = find_video_match
      if video_match[:success]
        return video_match
      end
    end

    match_result
  end

  # Handle disconnection when user swipes from a shared room
  def handle_room_disconnection
    return unless @waiting_entry&.room_id.present?

    room_id = @waiting_entry.room_id

    # Use database transaction to prevent race conditions
    ActiveRecord::Base.transaction do
      # Find all users in this room (without locking for count)
      users_in_room = VideoWaitingRoom.where(room_id: room_id)
      user_count = users_in_room.count

      if user_count > 1
        # Now lock the actual records we'll be updating
        users_in_room = users_in_room.lock

        # Disconnect all users from this room
        users_in_room.each do |user_entry|
          next if user_entry.user_id == @user_id # Skip current user, handle separately

          # Reset partner's entry and set them back to waiting
          reset_user_to_waiting_state(user_entry)

          # IMPORTANT: Trigger immediate match finding to prevent user being stuck
          # This ensures they get a new match right away instead of waiting
          trigger_new_match_for_user(user_entry.user_id)
        end
      end

      # Clean up current user's entry
      reset_user_to_waiting_state(@waiting_entry)

      # Mark this room as recently disconnected to prevent immediate reuse
      mark_room_as_recently_disconnected(room_id)
    end

  end

  # Helper method to reset user to waiting state consistently
  def reset_user_to_waiting_state(user_entry)
    if user_entry.user.role == 'staff'
      user_entry.update!(
        room_id: nil,
        partner_user_id: nil,
        status: 'waiting',
        match_type: 'staff',
        session_version: nil,
        updated_at: Time.current # Force timestamp update for status checks
      )
    else
      user_entry.update!(
        room_id: nil,
        partner_user_id: nil,
        status: 'waiting',
        match_type: 'real_user',
        session_version: nil,
        updated_at: Time.current # Force timestamp update for status checks
      )
    end
  end

  # Check and clean up stale room assignments
  def cleanup_stale_room_assignments

    # Find any waiting entries that might have stale room assignments
    stale_entries = VideoWaitingRoom.where(
      user_id: @user_id,
      status: 'waiting'
    ).where.not(room_id: nil)

    if stale_entries.any?

      stale_entries.each do |entry|
        room_id = entry.room_id

        # Check if other users are still in this room
        other_users_in_room = VideoWaitingRoom.where(room_id: room_id)
                                             .where.not(user_id: @user_id)

        if other_users_in_room.any?

          # Clean up other users in the stale room
          other_users_in_room.each do |other_entry|
            if other_entry.user.role == 'staff'
              other_entry.update!(
                room_id: nil,
                partner_user_id: nil,
                status: 'waiting',
                match_type: 'staff',
                session_version: nil
              )
            else
              other_entry.update!(
                room_id: nil,
                partner_user_id: nil,
                status: 'waiting',
                match_type: 'real_user',
                session_version: nil
              )
            end
          end
        end

        # Clean up current user's entry
        entry.update!(
          room_id: nil,
          partner_user_id: nil,
          session_version: nil
        )

        # Mark room as recently disconnected
        mark_room_as_recently_disconnected(room_id)
      end
    else
    end
  end

  # Ensure proper cleanup when user swipes
  def ensure_partner_cleanup_on_swipe
    return unless @waiting_entry&.room_id.present?

    room_id = @waiting_entry.room_id

    # Find partner in the same room
    partner_entry = VideoWaitingRoom.where(room_id: room_id)
                                   .where.not(user_id: @user_id)
                                   .first

    if partner_entry

      # Reset partner's entry
      if partner_entry.user.role == 'staff'
        partner_entry.update!(
          room_id: nil,
          partner_user_id: nil,
          status: 'waiting',
          match_type: 'staff',
          session_version: nil
        )
      else
        partner_entry.update!(
          room_id: nil,
          partner_user_id: nil,
          status: 'waiting',
          match_type: 'real_user',
          session_version: nil
        )
      end

      # Trigger new match for partner
      trigger_new_match_for_user(partner_entry.user_id)
    else
    end
  end

  # Mark room as recently disconnected to prevent immediate reuse
  def mark_room_as_recently_disconnected(room_id)
    # Store the room ID in Redis or a similar cache with a TTL
    # This prevents the same room from being reused immediately

    # Use Rails cache for global room tracking (works across server instances)
    Rails.cache.write("disconnected_room_#{room_id}", true, expires_in: 5.minutes)

    # Also keep local tracking for backward compatibility
    @recently_disconnected_rooms ||= Set.new
    @recently_disconnected_rooms.add(room_id)

    # Clean up old entries (older than 5 minutes)
    cleanup_old_disconnected_rooms
  end

  # Clean up old disconnected room entries
  def cleanup_old_disconnected_rooms
    return unless @recently_disconnected_rooms

    # Remove rooms older than 5 minutes
    # In production, use Redis TTL instead
    @recently_disconnected_rooms.clear if @recently_disconnected_rooms.size > 100
  end

  # Check if room was recently disconnected (global check)
  def room_recently_disconnected?(room_id)
    # Check global cache first
    if Rails.cache.exist?("disconnected_room_#{room_id}")
      return true
    end

    # Fallback to local tracking
    if @recently_disconnected_rooms&.include?(room_id)
      return true
    end

    false
  end

  # Handle staff disconnection properly
  def handle_staff_disconnection
    return unless @user.role == 'staff'

    # Staff users should always be available for new real user matches
    @waiting_entry.update!(
      room_id: nil,
      partner_user_id: nil,
      status: 'waiting',
      match_type: 'staff',
      session_version: nil
    )

  end

  # Trigger new match finding for a disconnected user
  def trigger_new_match_for_user(user_id)

    # Create a new instance of PoolMatchingService for the other user
    other_user_service = PoolMatchingService.new(user_id)

    # Find next match for them
    match_result = other_user_service.find_match

    if match_result[:success]

      # Create session for tracking
      other_user_service.create_session(match_result)
    else
    end
  rescue => e
  end

  # Create a session for tracking
  def create_session(match_data)
    return nil unless match_data[:success]

    # Map match_type to session_type
    session_type = case match_data[:match_type]
    when 'real_user'
      'user_to_user'
    when 'staff'
      'user_to_staff'
    when 'video'
      'user_to_video'
    else
      'user_to_user' # default fallback
    end

    session_attributes = {
      user_id: @user_id,
      pool_id: @pool&.id,
      sequence_id: @sequence&.id,
      session_id: generate_session_id,
      started_at: Time.current,
      session_type: session_type,
      partner_user_id: match_data[:partner_id],
      room_id: match_data[:room_id],
      status: 'active'
    }

    case match_data[:match_type]
    when 'real_user'
      session_attributes.merge!(
        partner_user_id: match_data[:partner_id]
      )
    when 'staff'
      session_attributes.merge!(
        staff_user_id: match_data[:partner_id]
      )
    when 'video'
      session_attributes.merge!(
        video_id: match_data[:video_id]
      )
    end
    VideoChatSession.create!(session_attributes)
  end

  # Method to handle user swiping while watching a video
  def handle_video_user_swipe

    # Staff users should never be in video mode - this is a safety check
    if @user.role == 'staff'
      @waiting_entry.update!(match_type: 'real_user', video_id: nil)
    end

    # Try to connect with real users first
    real_user_match = find_real_user_match
    if real_user_match[:success]
      return real_user_match
    end

    # If no real users available, try staff (but only for app users, never for staff users)
    if @user.role != 'staff'
      staff_match = find_staff_match
      if staff_match[:success]
        return staff_match
      end

      # If nothing else available, show next video (but only for app users)
      video_match = find_video_match
      if video_match[:success]
        return video_match
      end
    else
    end

    { success: false, reason: 'No matches available for video user' }
  end

  # Get updated sequence info for frontend auth store
  def get_updated_sequence_info
    return nil unless @user

    # Reload user to get latest data
    @user.reload

    {
      pool_id: @user.pool_id,
      sequence_id: @user.sequence_id,
      videos_watched_in_current_sequence: @user.videos_watched_in_current_sequence || 0,
      sequence_total_videos: @user.sequence_total_videos || 0
    }
  end

  # End a session and track analytics
  def end_session(room_id, reason = 'user_disconnect')
    session = VideoChatSession.find_by(
      room_id: room_id,
      user_id: @user_id,
      status: 'active'
    )

    return unless session

    # Calculate session duration
    duration = Time.current - session.started_at

    # Update session with end data
    session.update!(
      ended_at: Time.current,
      duration_seconds: duration.to_i,
      end_reason: reason,
      status: 'completed'
    )

    # Increment video count and check sequence advancement after successful match
    # increment_video_count_and_check_sequence_advancement if session.session_type == 'user_to_user'

    # Return session data for potential analytics
    {
      session_id: session.session_id,
      duration_seconds: duration.to_i,
      session_type: session.session_type,
      end_reason: reason
    }
  end

  # Get user's connection statistics for admin analytics
  def get_user_connection_stats
    sessions = VideoChatSession.where(user_id: @user_id, status: 'completed')

    {
      total_connections: sessions.count,
      total_duration_seconds: sessions.sum(:duration_seconds) || 0,
      total_duration_hours: (sessions.sum(:duration_seconds) || 0) / 3600.0,
      connections_by_type: sessions.group(:session_type).count,
      average_session_duration: sessions.average(:duration_seconds) || 0,
      last_connection: sessions.maximum(:ended_at),
      # User details can be accessed via associations when needed
      user_info: {
        gender: @user.gender,
        interested_in: @user.interested_in,
        age: @user.age
      }
    }
  end

  private

  # Helper method to update user's sequence information
  def update_user_sequence_info(sequence, reset_video_count: true)
    update_attributes = {
      sequence_id: sequence.id,
      sequence_total_videos: sequence.video_count
    }

    update_attributes[:videos_watched_in_current_sequence] = 0 if reset_video_count

    @user.update!(update_attributes)

    # Update instance variable
    @sequence = sequence

    if reset_video_count
    end
  end

  # Helper method to find first active sequence in pool
  def find_first_active_sequence
    @pool.sequences.active.ordered.first
  end

  # Base query builder for real users
  def build_base_user_query
    VideoWaitingRoom.waiting
                    .joins(:user)
                    .where.not(user_id: @user_id)
                    .where(pool_id: @pool.id)
                    .where(sequence_id: @sequence.id)
                    .where(room_id: nil)
                    .where(session_version: nil) # Only match users with no active session
                    .where.not(users: { id: users_in_active_sessions })
                    .where.not(users: { id: recently_disconnected_users })  # Prevent matching with recently disconnected users
                    # .where('video_waiting_rooms.updated_at > ?', 5.minutes.ago) # Only match recently active users
  end

  # Get list of users who were recently disconnected from the same room
  def recently_disconnected_users
    return [] unless @waiting_entry&.room_id.present?

    # Get users who were in the same room within the last 5 minutes
    recent_room_users = VideoWaitingRoom.where(
      room_id: @waiting_entry.room_id,
      updated_at: 5.minutes.ago..Time.current
    ).pluck(:user_id)

    recent_room_users
  end

  # Unified method for building queries that exclude users in active sessions
  def build_query_with_availability_check(base_query)
    base_query.where.not(users: { id: users_in_active_sessions })
  end

  # Helper method to check if user is in active session
  def users_in_active_sessions
    VideoWaitingRoom.where.not(room_id: nil)
                    .where(status: 'matched')
                    .pluck(:user_id)
  end

  # Find the appropriate sequence for app users (non-staff)
  def find_sequence_for_user
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
    first_sequence = find_first_active_sequence
    if first_sequence

      # Update user's sequence info in database
      update_user_sequence_info(first_sequence, reset_video_count: true)

      return first_sequence
    else
      return nil
    end
  end

  # Reassign user to a valid sequence if their current one is inactive
  def reassign_user_to_valid_sequence
    return unless @user && @pool

    # Find first active sequence in the pool
    first_sequence = find_first_active_sequence
    if first_sequence

      # Update user's sequence info
      update_user_sequence_info(first_sequence, reset_video_count: true)

    else
    end
  end

  # Unified gender matching logic for both real users and staff
  def find_match_with_gender_preference_logic(base_query, match_type)
    # Try to find match with preferred gender first (avoiding recent matches)// this is for POOl A only
    if @user.interested_in.present? && @user.interested_in != 'other' && @user.pool.name == 'Pool A'
      preferred_match = find_match_with_gender_preference_and_avoid_repeats(base_query, @user.interested_in)
      if preferred_match
        return { success: true, match: preferred_match }
      end

      # If no preferred gender available, try same gender as fallback
      same_gender = @user.gender
      if same_gender.present?
        same_gender_match = find_match_with_gender_preference_and_avoid_repeats(base_query, same_gender)
        if same_gender_match
          return { success: true, match: same_gender_match }
        end
      end
    end

    # If no gender preference or no gender-based matches, try any available user (avoiding repeats)
    any_match = find_match_avoiding_repeats(base_query)
    if any_match
      return { success: true, match: any_match }
    end

    # If still no match, try with repeats allowed (last resort)
    last_resort_match = base_query.first
    if last_resort_match
      return { success: true, match: last_resort_match }
    end

    { success: false, reason: 'No matches available' }
  end

  # Core matching methods with gender-based query support
  def find_real_user_match

    # Build base query for real user matching
    base_query = build_real_user_query

    # Use unified gender matching logic
    match_result = find_match_with_gender_preference_logic(base_query, 'real_user')

    if match_result[:success]
      return create_real_user_match(match_result[:match])
    end

    return { success: false, reason: 'No other users available' }
  end

  def find_staff_match
    # Staff users should NEVER try to match with other staff
    if @user.role == 'staff'
      return { success: false, reason: 'Staff users cannot match with other staff' }
    end

    # Build base query for staff matching
    base_query = build_staff_query

    # Use unified gender matching logic
    match_result = find_match_with_gender_preference_logic(base_query, 'staff')

    if match_result[:success]
      return create_staff_match(match_result[:match])
    end

    return { success: false }
  end

  def find_video_match
    # Staff users should NEVER be matched with videos - they only wait for real users
    if @user.role == 'staff'
      return { success: false, reason: 'Staff users do not watch videos' }
    end

    # Check if user should see video next based on sequence logic
    should_show = should_show_video_next?
    return { success: false, reason: 'should_show_video_next returned false' } unless should_show

    # Get next available video user hasn't seen
    available_video = get_next_video_for_user
    return { success: false, reason: 'No available video found' } unless available_video

    # Create room and match with video
    create_video_match(available_video)
  end

  # Query building methods for easy customization
  def build_real_user_query
    # App users can only be in ONE session at a time
    # Check if user is already in an active session
    build_base_user_query
      .where(match_type: 'real_user')
      .order(:joined_at)
  end

  def build_staff_query
    # Staff can only be in ONE session at a time
    # Check if staff user is already in an active session

    query = VideoWaitingRoom.where(match_type: 'staff')
                            .where(status: 'waiting')
                            .where(pool_id: @pool.id)
                            .where(sequence_id: @sequence.id)
                            .where.not(user_id: @user_id)
                            .where(room_id: nil) # Ensure staff is not in any room
                            .where(session_version: nil) # Ensure no active session
                            # .where('video_waiting_rooms.updated_at > ?', 5.minutes.ago) # Only recently active staff
                            .joins(:user)

    staff_count = query.count

    query
  end

  # Gender preference methods - easy to extend and customize
  def find_match_with_gender_preference(base_query, preferred_gender)
    base_query.where(users: { gender: preferred_gender }).first
  end

  def find_staff_with_gender_preference(base_query, preferred_gender)
    base_query.where(users: { gender: preferred_gender }).first
  end

  # Unified method for finding matches with gender preference and repeat avoidance
  def find_match_with_gender_preference_and_avoid_repeats_unified(base_query, preferred_gender, is_staff: false)
    # First try to find someone of preferred gender who hasn't been matched recently
    preferred_users = base_query.where(users: { gender: preferred_gender })

    # Filter out recent matches (last 24 hours)
    preferred_users = filter_out_recent_matches(preferred_users)

    preferred_users.first
  end

  # Use the unified method for both real users and staff
  def find_match_with_gender_preference_and_avoid_repeats(base_query, preferred_gender)
    find_match_with_gender_preference_and_avoid_repeats_unified(base_query, preferred_gender, is_staff: false)
  end

  def find_staff_with_gender_preference_and_avoid_repeats(base_query, preferred_gender)
    find_match_with_gender_preference_and_avoid_repeats_unified(base_query, preferred_gender, is_staff: true)
  end

  # Unified method for finding matches avoiding repeats
  def find_match_avoiding_repeats_unified(base_query, is_staff: false)
    # Filter out recent matches (last 24 hours)
    filtered_query = filter_out_recent_matches(base_query)
    filtered_query.first
  end

  # Use the unified method for both real users and staff
  def find_match_avoiding_repeats(base_query)
    find_match_avoiding_repeats_unified(base_query, is_staff: false)
  end

  def find_staff_avoiding_repeats(base_query)
    find_match_avoiding_repeats_unified(base_query, is_staff: true)
  end

  # Filter out users who have been matched recently with current user
  def filter_out_recent_matches(query)
    # Get list of users matched with current user in last 24 hours
    recent_partner_ids = VideoChatSession.where(
      user_id: @user_id,
      created_at: 24.hours.ago..Time.current,
      status: ['active', 'completed']
    ).pluck(:partner_user_id).compact

    if recent_partner_ids.any?
      query = query.where.not(users: { id: recent_partner_ids })
    end

    query
  end

  def add_gender_preference(query)
    case @user.interested_in
    when 'male'
      query.where(users: { gender: 'male' })
    when 'female'
      query.where(users: { gender: 'female' })
    when 'other'
      query.where(users: { gender: 'other' })
    else
      query # No preference, return all
    end
  end

  # Advanced gender matching - can be easily extended
  def add_advanced_gender_matching(query)
    # Example: Add more sophisticated gender matching logic here
    # This could include:
    # - Mutual interest checking
    # - Gender fluidity support
    # - Custom preference algorithms

    # For now, just return the basic query
    query
  end

  # Sequence management methods
  def increment_video_count_and_check_sequence_advancement
    return unless @user && @sequence

    # Get current video count from user
    current_video_count = @user.videos_watched_in_current_sequence || 0
    new_video_count = current_video_count + 1

    # Update user's video count
    @user.update!(videos_watched_in_current_sequence: new_video_count)

    # Check if sequence should advance
    if new_video_count >= @sequence.video_count
      advance_to_next_sequence
    else
    end
  end

  def advance_to_next_sequence
    return false unless @user && @pool

    # Find next sequence in the pool
    next_sequence = find_next_sequence_in_pool

    if next_sequence
      # Update user's sequence and reset video count
      update_user_sequence_info(next_sequence, reset_video_count: true)
      @sequence = next_sequence  # Update instance variable

      return true
    else
      # No more sequences, wrap back to first sequence
      first_sequence = find_first_active_sequence
      if first_sequence
        update_user_sequence_info(first_sequence, reset_video_count: true)
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
    next_sequence = active_sequences.find { |seq| seq.position > current_position && seq.videos.active.any? }

    if next_sequence
      next_sequence
    else
      nil
    end
  end

  # Helper methods
  def user_available_for_matching?(user_id)
    # Check if user is not already in an active session
    !VideoWaitingRoom.exists?(
      user_id: user_id,
      status: 'matched',
      room_id: nil
    )
  end

  def should_show_video_next?
    # Staff users should NEVER see videos - they only wait for real users
    if @user.role == 'staff'
      return false
    end

    return false unless @sequence

    # Check if there are any real users waiting
    real_users_waiting = build_real_user_query.count

    # Check if there are any staff available
    staff_available = build_staff_query.count

    # Only show video if no real users or staff are available
    should_show = real_users_waiting == 0 && staff_available == 0

    # Also check if there are actually videos available
    has_videos = @sequence.videos.active.exists?

    should_show && has_videos
  end

  def get_next_video_for_user
    return nil unless @sequence

    # Get any available video from current sequence
    videos = @sequence.videos.active
    videos.first
  end

  def get_next_video_for_user_no_repeats
    return nil unless @sequence

    # Get videos that user hasn't watched yet (no video chat sessions with these videos)
    watched_video_ids = @user.watched_video_ids_in_sequence(@sequence.id)
    unwatched_videos = @sequence.videos.active.where.not(id: watched_video_ids).order(:created_at)

    unwatched_videos.first
  end

  def get_next_video_for_user_with_repeats
    return nil unless @sequence
    return nil unless @sequence.videos.active.any?

    # First try to get videos that user hasn't watched yet (reuse existing method)
    unwatched_video = get_next_video_for_user_no_repeats
    return unwatched_video if unwatched_video

    # If all videos have been watched, implement rotation logic to avoid consecutive repeats
    get_next_video_in_rotation
  end

  private

  # Get the next video in rotation to avoid consecutive repeats
  def get_next_video_in_rotation
    all_videos = @sequence.videos.active.order(:created_at).to_a

    # If only one video, return it
    return all_videos.first if all_videos.size == 1

    # Get the most recently watched video (last session created)
    last_watched_video = @user.video_chat_sessions
      .where(sequence_id: @sequence.id)
      .joins(:video)
      .where(videos: { status: :active })
      .order(created_at: :desc)
      .first&.video

    if last_watched_video
      # Find the next video in rotation (after the last watched one)
      current_index = all_videos.find_index { |v| v.id == last_watched_video.id }
      next_index = current_index ? (current_index + 1) % all_videos.size : 0
      all_videos[next_index]
    else
      # If no previous session, return the oldest video
      all_videos.first
    end
  end

  def create_real_user_match(other_user)
    # Use database transaction with locking to prevent race conditions
    ActiveRecord::Base.transaction do
      # Lock the other user to prevent concurrent modifications
      other_user.reload.lock!

      # Double-check availability after locking
      if other_user.status != 'waiting' || other_user.room_id.present?
        raise ActiveRecord::Rollback, 'Other user no longer available'
      end

      # ALWAYS create a new room ID to prevent WebRTC m-lines conflicts
      # This ensures fresh WebRTC context for each connection
      room_id = create_room_id

      # Generate unique session version to prevent stale signals
      session_version = generate_session_version(room_id)
      match_users_in_room(@waiting_entry, other_user, room_id, 'real_user', session_version)

      # Increment video count after successful match
      increment_video_count_after_match

      return {
        success: true,
        match_type: 'real_user',
        partner_id: other_user.user_id,
        room_id: room_id,
        session_version: session_version,
        is_initiator: @user_id < other_user.user_id  # Lower user ID becomes initiator
      }
    end
  rescue ActiveRecord::Rollback => e
    return { success: false, reason: e.message }
  rescue => e
    return { success: false, reason: 'Unexpected error occurred' }
  end

  def create_staff_match(staff_assignment)
    # Use database transaction with locking to prevent race conditions
    ActiveRecord::Base.transaction do
      # Lock the staff assignment to prevent concurrent modifications
      staff_assignment.reload.lock!

      # Verify staff is still available
      # if staff_assignment.user.status != 'online' && staff_assignment.user.status != 'in_chat'
      #   raise ActiveRecord::Rollback, 'Staff no longer available'
      # end

      # Find the staff user's waiting room entry
      staff_waiting_entry = VideoWaitingRoom.find_by(user_id: staff_assignment.user.id, status: 'waiting')
      unless staff_waiting_entry
        raise ActiveRecord::Rollback, 'Staff user not in waiting room'
      end

      # ALWAYS create a new room ID to prevent WebRTC m-lines conflicts
      # This ensures fresh WebRTC context for each connection
      room_id = create_room_id

      # Generate unique session version to prevent stale signals
      session_version = generate_session_version(room_id)

      # Now pass both waiting room entries to ensure both get updated
      match_users_in_room(@waiting_entry, staff_waiting_entry, room_id, 'staff', session_version)

      # Increment video count after successful match
      increment_video_count_after_match

      return {
        success: true,
        match_type: 'staff',
        partner_id: staff_assignment.user.id,
        room_id: room_id,
        session_version: session_version,
        is_initiator: @user_id < staff_assignment.user.id  # Lower user ID becomes initiator
      }
    end
  rescue ActiveRecord::Rollback => e
    return { success: false, reason: e.message }
  rescue => e
    return { success: false, reason: 'Unexpected error occurred' }
  end

  def match_users_in_room(current_entry, other_entry, room_id, match_type, session_version = nil, partner_id = nil, video_id = nil)

    # Safety check: Staff users should never be matched with videos
    if @user.role == 'staff' && match_type == 'video'
      raise "Staff users cannot be matched with videos"
    end

    # Determine initiator based on user ID (lower ID becomes initiator for consistency)
    # This ensures consistent initiator assignment for each new connection
    is_current_user_initiator = @user_id < (other_entry&.user_id || 999999)

    # Update current user's entry with their unique session version
    current_entry.update!(
      room_id: room_id,
      partner_user_id: other_entry&.user_id,
      status: 'matched',
      is_initiator: is_current_user_initiator,
      match_type: match_type,
      video_id: video_id,
      session_version: session_version
    )

    # Update other user's entry with their unique session version
    if other_entry
      # The other user is NOT the initiator (they're the receiver)
      other_entry.update!(
        room_id: room_id,
        partner_user_id: @user_id,
        status: 'matched',
        is_initiator: !is_current_user_initiator, # Opposite of current user
        match_type: match_type,
        session_version: session_version
      )
    end

    # Keep waiting room entries with 'matched' status for frontend detection
  end

  def create_room_id
    "room_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end

  def generate_session_id
    "session_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end

  def generate_session_version(room_id)
    # Use room_id hash + timestamp + random to ensure uniqueness even for simultaneous matches
    # This prevents both users from getting the same session version when matched at the same time
    room_hash = Digest::MD5.hexdigest(room_id)[0..7]
    "version_#{Time.current.to_i}_#{room_hash}_#{SecureRandom.hex(4)}"
  end

  # NEW: Real user matching methods
  def find_real_user_match_no_repeats

    base_query = build_real_user_query_no_repeats
    match_result = find_match_with_gender_preference_logic(base_query, 'real_user')

    if match_result[:success]
      return create_real_user_match(match_result[:match])
    end

    { success: false, reason: 'No real users available (no repeats)' }
  end

  def find_real_user_match_with_repeats

    base_query = build_real_user_query_with_repeats
    match_result = find_match_with_gender_preference_logic(base_query, 'real_user')

    if match_result[:success]
      return create_real_user_match(match_result[:match])
    end

    { success: false, reason: 'No real users available (even with repeats)' }
  end

  # NEW: Staff matching methods
  def find_staff_match_no_repeats
    return { success: false, reason: 'Staff users cannot match with other staff' } if @user.role == 'staff'

    base_query = build_staff_query_no_repeats
    match_result = find_match_with_gender_preference_logic(base_query, 'staff')

    if match_result[:success]
      return create_staff_match(match_result[:match])
    end

    { success: false, reason: 'No staff available (no repeats)' }
  end

  def find_staff_match_with_repeats
    return { success: false, reason: 'Staff users cannot match with other staff' } if @user.role == 'staff'

    base_query = build_staff_query_with_repeats
    match_result = find_match_with_gender_preference_logic(base_query, 'staff')
    if match_result[:success]
      return create_staff_match(match_result[:match])
    end

    { success: false, reason: 'No staff available (even with repeats)' }
  end

  # NEW: Video matching methods
  def find_video_match_no_repeats
    return { success: false, reason: 'Staff users do not watch videos' } if @user.role == 'staff'

    # Check if user should see video next based on sequence logic
    should_show = should_show_video_next?
    return { success: false, reason: 'should_show_video_next returned false' } unless should_show

    # Get next available video user hasn't seen
    available_video = get_next_video_for_user_no_repeats
    return { success: false, reason: 'No available video found (no repeats)' } unless available_video

    create_video_match(available_video)
  end

  def find_video_match_with_repeats
    return { success: false, reason: 'Staff users do not watch videos' } if @user.role == 'staff'

    # Check if user should see video next based on sequence logic
    should_show = should_show_video_next?
    return { success: false, reason: 'should_show_video_next returned false' } unless should_show

    # Get any available video (including repeats)
    available_video = get_next_video_for_user_with_repeats
    return { success: false, reason: 'No available video found (even with repeats)' } unless available_video

    create_video_match(available_video)
  end

  def create_video_match(available_video)
    room_id = create_room_id
    session_version = generate_session_version(room_id)

    match_users_in_room(@waiting_entry, nil, room_id, 'video', session_version, nil, available_video.id)

    # Increment video count after successful match
    increment_video_count_after_match

    # Get video URL for frontend
    video_url = nil
    if available_video.video_file.attached?
      video_url = available_video.video_file.url
    else
    end

    {
      success: true,
      match_type: 'video',
      video_id: available_video.id,
      video_url: video_url,
      video_name: available_video.name,
      room_id: room_id,
      session_version: session_version,
      is_initiator: true
    }
  end

  def build_real_user_query_no_repeats
    build_base_user_query
      .where(match_type: 'real_user')
      .where.not(users: { id: recently_disconnected_users })
      .where.not(users: { id: users_matched_recently })
      .order(:joined_at)
  end

  def build_real_user_query_with_repeats
    # For repeats, we want to prioritize users based on when they were first matched
    # This ensures we get the earliest repeat (e.g., user7 at 7:20 before user8 at 7:25)

    # Get users matched recently, ordered by first match time
    recently_matched_users = VideoChatSession.where(
      user_id: @user_id,
      created_at: 10.minutes.ago..Time.current,
      status: ['active', 'completed']
    ).order(:created_at).pluck(:partner_user_id).compact

    # Build base query excluding recently disconnected users
    base_query = build_base_user_query
      .where(match_type: 'real_user')
      .where.not(users: { id: recently_disconnected_users })

    # If we have recently matched users, prioritize them by match order
    if recently_matched_users.any?
      # Use CASE statement to order by match priority (earliest first)
      order_clause = recently_matched_users.map.with_index { |user_id, index|
        "CASE WHEN users.id = #{user_id} THEN #{index} ELSE #{recently_matched_users.length} END"
      }.join(', ')

      base_query = base_query.joins(:user)
                             .order(Arel.sql(order_clause))
                             .order(:joined_at) # Secondary sort by join time

    else
      # No recent matches, use default ordering
      base_query = base_query.joins(:user).order(:joined_at)
    end

    base_query
  end

  def build_staff_query_no_repeats
    # Staff can only be in ONE session at a time
    # Check if staff user is already in an active session

    query = VideoWaitingRoom.where(match_type: 'staff')
                            .where(status: 'waiting')
                            .where(pool_id: @pool.id)
                            .where(sequence_id: @sequence.id)
                            .where.not(user_id: @user_id)
                            .where.not(user_id: recently_disconnected_users)
                            .where.not(user_id: staff_matched_recently)
                            .where(session_version: nil)
                            .joins(:user)
                            .order(:joined_at)

    staff_count = query.count

    query
  end

  def build_staff_query_with_repeats
    # Staff can only be in ONE session at a time
    # Check if staff user is already in an active session

    query = VideoWaitingRoom.where(match_type: 'staff')
                            .where(status: 'waiting')
                            .where(pool_id: @pool.id)
                            .where(sequence_id: @sequence.id)
                            .where.not(user_id: @user_id)
                            .where.not(user_id: recently_disconnected_users)
                            .where(session_version: nil)
                            .joins(:user)
                            .order(:joined_at)

    staff_count = query.count

    query
  end

  # NEW: Helper methods for repeat avoidance
  def users_matched_recently
    VideoChatSession.where(
      user_id: @user_id,
      created_at: 10.minutes.ago..Time.current,
      status: ['active', 'completed']
    ).pluck(:partner_user_id).compact
  end

  def staff_matched_recently
    VideoChatSession.where(
      user_id: @user_id,
      session_type: 'user_to_staff',
      created_at: 10.minutes.ago..Time.current,
      status: ['active', 'completed']
    ).pluck(:partner_user_id).compact
  end

  def check_and_advance_sequence_if_needed
    return unless @user && @sequence

    # Get current video count from user
    current_video_count = @user.videos_watched_in_current_sequence || 0

    # Check if sequence should advance
    if current_video_count >= @sequence.video_count
      advance_to_next_sequence
    else
    end
  end

  # Increment video count after successful match completion
  def increment_video_count_after_match
    return unless @user && @sequence

    # Get current video count from user
    current_video_count = @user.videos_watched_in_current_sequence || 0
    new_video_count = current_video_count + 1

    # Update user's video count
    @user.update!(videos_watched_in_current_sequence: new_video_count)

  end
end
