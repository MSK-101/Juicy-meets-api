class PoolMatchingService
  include ActiveSupport::Configurable

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

  # Main matching method - tries to find the best match with retry logic
  def find_match(max_retries = 3)
    Rails.logger.info "🔍 Finding match for user #{@user_id} in pool #{@pool&.name} (ID: #{@pool&.id}), sequence #{@sequence&.name} (ID: #{@sequence&.id})"

    # Add specific logging for staff users
    if @user.role == 'staff'
      Rails.logger.info "👨‍💼 Staff user #{@user_id} - will only match with REAL APP USERS, never with other staff or videos"
    end

    # Check if current user is currently watching a video
    if @waiting_entry&.match_type == 'video' && @waiting_entry&.room_id.present?
      Rails.logger.info "🔄 Current user #{@user_id} is watching a video, handling video user swipe..."
      return handle_video_user_swipe
    end

    attempt = 0
    while attempt < max_retries
      attempt += 1
      Rails.logger.info "🔄 Match attempt #{attempt}/#{max_retries} for user #{@user_id}"

      # Step 1: Try to match with another real user from same pool
      Rails.logger.info "🔍 Step 1: Trying real user match..."
      real_user_match = find_real_user_match
      if real_user_match[:success]
        Rails.logger.info "✅ Real user match successful!"
        return real_user_match
      end

      # Step 2: Try to match with staff (ONLY for app users, never for staff users)
      if @user.role != 'staff'
        Rails.logger.info "🔍 Step 2: Trying staff match for app user..."
        staff_match = find_staff_match
        if staff_match[:success]
          Rails.logger.info "✅ Staff match successful!"
          return staff_match
        end
      else
        Rails.logger.info "👨‍💼 Step 2: Skipping staff match for staff user #{@user_id} - staff only match with real app users"
      end

      # Step 3: Check if we should show video next (ONLY for app users, never for staff)
      if @user.role != 'staff'
        Rails.logger.info "🔍 Step 3: Checking video availability for app user..."
        video_match = find_video_match
        if video_match[:success]
          Rails.logger.info "✅ Video match successful!"
          return video_match
        end
      else
        Rails.logger.info "👨‍💼 Step 3: Skipping video check for staff user #{@user_id} - staff only wait for real app users"
      end

      # If we get here, no match was found
      if attempt < max_retries
        Rails.logger.info "⏳ No match found on attempt #{attempt}, retrying in 2 seconds..."
        sleep(2) # Wait before retry

        # Refresh user data for next attempt
        @user.reload
        @waiting_entry.reload if @waiting_entry
      end
    end

    # Special message for staff users who couldn't find a match
    if @user.role == 'staff'
      Rails.logger.info "👨‍💼 Staff user #{@user_id} - no real app users available, staying in wait queue for real app users only"
      return { success: false, reason: 'Staff users wait for real app users only - no real app users currently available' }
    end

    Rails.logger.info "❌ No match found for user #{@user_id} after #{max_retries} attempts"
    { success: false, reason: 'No matches available after retries' }
  end

  # Find next match when user swipes or disconnects
  def find_next_match
    return { error: 'User not found' } unless @user

    # First, handle disconnection of both users if they were in a room together
    handle_room_disconnection

    # DON'T increment video count here - only increment AFTER successful match completion
    # increment_video_count_and_check_sequence_advancement  ← REMOVED

    # Try to find next match
    find_match
  end

  # Handle disconnection when user swipes from a shared room
  def handle_room_disconnection
    return unless @waiting_entry&.room_id.present?

    room_id = @waiting_entry.room_id
    Rails.logger.info "🔄 User #{@user_id} swiping from room #{room_id}, handling disconnection"

    # Find all users in this room
    users_in_room = VideoWaitingRoom.where(room_id: room_id)

    if users_in_room.count > 1
      Rails.logger.info "🔄 Found #{users_in_room.count} users in room #{room_id}, disconnecting all"

      # Disconnect all users from this room
      users_in_room.each do |user_entry|
        # Don't disconnect the current user - they're already being handled
        next if user_entry.user_id == @user_id

        Rails.logger.info "🔄 Disconnecting user #{user_entry.user_id} from room #{room_id}"

        # Reset their waiting entry for new matching
        user_entry.update!(
          room_id: nil,
          partner_user_id: nil,
          status: 'waiting',
          match_type: 'real_user'
        )

        # Trigger new match finding for the other user
        trigger_new_match_for_user(user_entry.user_id)
      end
    end

    # Clean up current user's entry
    @waiting_entry.update!(
      room_id: nil,
      partner_user_id: nil,
      status: 'waiting',
      match_type: 'real_user'
    )
  end

  # Trigger new match finding for a disconnected user
  def trigger_new_match_for_user(user_id)
    Rails.logger.info "🔄 Triggering new match for disconnected user #{user_id}"

    # Create a new instance of PoolMatchingService for the other user
    other_user_service = PoolMatchingService.new(user_id)

    # Find next match for them
    match_result = other_user_service.find_match

    if match_result[:success]
      Rails.logger.info "✅ Disconnected user #{user_id} got new match: #{match_result[:match_type]}"

      # Create session for tracking
      other_user_service.create_session(match_result)
    else
      Rails.logger.info "❌ Disconnected user #{user_id} no match available, staying in queue"
    end
  rescue => e
    Rails.logger.error "❌ Error triggering new match for user #{user_id}: #{e.message}"
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
      # Use session_type instead of match_type
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
    Rails.logger.info "🔄 Handling swipe for video user #{@user_id}..."

    # Staff users should never be in video mode - this is a safety check
    if @user.role == 'staff'
      Rails.logger.warn "⚠️ Staff user #{@user_id} was somehow in video mode - resetting to real user mode"
      @waiting_entry.update!(match_type: 'real_user', video_id: nil)
    end

    # Try to connect with real users first
    real_user_match = find_real_user_match
    if real_user_match[:success]
      Rails.logger.info "✅ Video user connected with real user!"
      return real_user_match
    end

    # If no real users available, try staff (but only for app users, never for staff users)
    if @user.role != 'staff'
      staff_match = find_staff_match
      if staff_match[:success]
        Rails.logger.info "✅ Video user connected with staff!"
        return staff_match
      end

      # If nothing else available, show next video (but only for app users)
      Rails.logger.info "🔄 No connections available, showing next video..."
      video_match = find_video_match
      if video_match[:success]
        Rails.logger.info "✅ Next video found for video user!"
        return video_match
      end
    else
      Rails.logger.info "👨‍💼 Staff user #{@user_id} - waiting for real app users only, no staff or video fallback"
    end

    Rails.logger.info "❌ No matches available for video user swipe"
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

    Rails.logger.info "🔚 Session #{session.session_id} ended for user #{@user_id}, duration: #{duration.to_i}s, reason: #{reason}"

    # Increment video count and check sequence advancement after successful match
    increment_video_count_and_check_sequence_advancement if session.session_type == 'user_to_user'

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
  def update_user_sequence_info(sequence, reset_video_count: false)
    update_attributes = {
      sequence_id: sequence.id,
      sequence_total_videos: sequence.video_count
    }

    update_attributes[:videos_watched_in_current_sequence] = 0 if reset_video_count

    @user.update!(update_attributes)

    # Update instance variable
    @sequence = sequence

    Rails.logger.info "📊 User #{@user_id} sequence updated: #{sequence.name} (ID: #{sequence.id})"
    if reset_video_count
      Rails.logger.info "📊 Video count reset to 0 for new sequence"
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
                    .where.not(users: { id: users_in_active_sessions })
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
      Rails.logger.info "👨‍💼 User #{@user_id} is staff, using fixed sequence from staff_assignment"
      return @user.staff_assignment&.sequence
    end

    # For app users, determine sequence based on their current state
    if @user.sequence_id.present?
      # User has a sequence_id, find that sequence
      sequence = @pool.sequences.active.find_by(id: @user.sequence_id)
      if sequence
        Rails.logger.info "👤 App user #{@user_id} has sequence_id #{@user.sequence_id}, using sequence: #{sequence.name}"

        # Ensure user has sequence_total_videos set
        if @user.sequence_total_videos.nil?
          @user.update!(sequence_total_videos: sequence.video_count)
          Rails.logger.info "📊 Set sequence_total_videos to #{sequence.video_count} for user #{@user_id}"
        end

        return sequence
      else
        Rails.logger.warn "⚠️ User #{@user_id} has invalid sequence_id #{@user.sequence_id}, will assign new sequence"
      end
    end

    # If no valid sequence_id, assign the first sequence in the pool
    first_sequence = find_first_active_sequence
    if first_sequence
      Rails.logger.info "👤 App user #{@user_id} assigned to first sequence: #{first_sequence.name} (ID: #{first_sequence.id})"

      # Update user's sequence info in database
      update_user_sequence_info(first_sequence, reset_video_count: true)

      return first_sequence
    else
      Rails.logger.error "❌ No active sequences found in pool #{@pool.name} for user #{@user_id}"
      return nil
    end
  end

  # Reassign user to a valid sequence if their current one is inactive
  def reassign_user_to_valid_sequence
    return unless @user && @pool

    # Find first active sequence in the pool
    first_sequence = find_first_active_sequence
    if first_sequence
      Rails.logger.info "🔄 Reassigning user #{@user_id} to sequence: #{first_sequence.name} (ID: #{first_sequence.id})"

      # Update user's sequence info
      update_user_sequence_info(first_sequence, reset_video_count: true)

      Rails.logger.info "✅ User #{@user_id} reassigned to sequence #{first_sequence.name}"
    else
      Rails.logger.error "❌ No active sequences available for reassignment in pool #{@pool.name}"
    end
  end

  # Core matching methods with gender-based query support
  def find_real_user_match
    Rails.logger.info "👥 Looking for real user match in pool #{@pool.name}, sequence #{@sequence.name}"

    # Build base query for real user matching
    base_query = build_real_user_query

    # Use unified gender matching logic
    match_result = find_match_with_gender_preference_logic(base_query, 'real_user')

    if match_result[:success]
      return create_real_user_match(match_result[:match])
    end

    Rails.logger.info "❌ No other users available for matching in pool #{@pool.name}, sequence #{@sequence.name}"
    return { success: false, reason: 'No other users available' }
  end

  def find_staff_match
    # Staff users should NEVER try to match with other staff
    if @user.role == 'staff'
      Rails.logger.warn "⚠️ Staff user #{@user_id} attempted to find staff match - this should never happen!"
      return { success: false, reason: 'Staff users cannot match with other staff' }
    end

    Rails.logger.info "👨‍💼 Looking for staff match for app user #{@user_id} in pool #{@pool.name}, sequence #{@sequence.name}"

    # Build base query for staff matching
    # debugger
    base_query = build_staff_query

    # Use unified gender matching logic
    match_result = find_match_with_gender_preference_logic(base_query, 'staff')

    if match_result[:success]
      return create_staff_match(match_result[:match])
    end

    return { success: false }
  end

  # Unified gender matching logic for both real users and staff
  def find_match_with_gender_preference_logic(base_query, match_type)
    # Try to find match with preferred gender first (avoiding recent matches)// this is for POOl A only
    if @user.interested_in.present? && @user.interested_in != 'other' && @user.pool.name == 'Pool A'
      preferred_match = find_match_with_gender_preference_and_avoid_repeats(base_query, @user.interested_in)
      if preferred_match
        Rails.logger.info "👥 Found preferred gender match: #{preferred_match.user_id || preferred_match.user.id}"
        return { success: true, match: preferred_match }
      end

      # If no preferred gender available, try same gender as fallback
      Rails.logger.info "👥 No preferred gender (#{@user.interested_in}) available, trying same gender fallback"
      same_gender = @user.gender
      if same_gender.present?
        same_gender_match = find_match_with_gender_preference_and_avoid_repeats(base_query, same_gender)
        if same_gender_match
          Rails.logger.info "👥 Found same gender fallback match: #{same_gender_match.user_id || same_gender_match.user.id}"
          return { success: true, match: same_gender_match }
        end
      end
    end
    # debugger
    # If no gender preference or no gender-based matches, try any available user (avoiding repeats)
    Rails.logger.info "👥 Trying match without gender preference (avoiding repeats)"
    any_match = find_match_avoiding_repeats(base_query)
    if any_match
      Rails.logger.info "👥 Found any available match: #{any_match.user_id || any_match.user.id}"
      return { success: true, match: any_match }
    end

    # If still no match, try with repeats allowed (last resort)
    Rails.logger.info "👥 No matches available, trying with repeats allowed (last resort)"
    last_resort_match = base_query.first
    if last_resort_match
      Rails.logger.info "👥 Found last resort match (with repeat): #{last_resort_match.user_id || last_resort_match.user.id}"
      return { success: true, match: last_resort_match }
    end

    { success: false, reason: 'No matches available' }
  end

  def find_video_match
    # Staff users should NEVER be matched with videos - they only wait for real users
    if @user.role == 'staff'
      Rails.logger.info "👨‍💼 Staff user #{@user_id} should not be matched with videos - waiting for real users only"
      return { success: false, reason: 'Staff users do not watch videos' }
    end

    Rails.logger.info "🎥 Starting video match process for app user #{@user_id}..."

    # Check if user should see video next based on sequence logic
    should_show = should_show_video_next?
    return { success: false, reason: 'should_show_video_next returned false' } unless should_show

    # Get next available video user hasn't seen
    available_video = get_next_video_for_user
    return { success: false, reason: 'No available video found' } unless available_video

    # Create room and match with video
    room_id = create_room_id
    Rails.logger.info "🎥 Creating room #{room_id} for video #{available_video.id}"
    session_version = generate_session_version(room_id)

    match_users_in_room(@waiting_entry, nil, room_id, 'video', session_version, nil, available_video.id)

    Rails.logger.info "✅ User #{@user_id} matched with video #{available_video.id} in sequence #{@sequence.name}"

    # NOW increment video count after successful video match
    increment_video_count_and_check_sequence_advancement

    # Get video URL for frontend
    video_url = nil
    if available_video.video_file.attached?
      video_url = available_video.video_file.url
      Rails.logger.info "🎥 Video URL generated: #{video_url}"
    else
      Rails.logger.warn "🎥 Video file not attached for video #{available_video.id}"
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
    Rails.logger.info "🔍 Building staff query for pool #{@pool.id}, sequence #{@sequence.id}"

    query = VideoWaitingRoom.where(match_type: 'staff')
                            .where(status: 'waiting')
                            .where(pool_id: @pool.id)
                            .where(sequence_id: @sequence.id)
                            .where.not(user_id: @user_id)
                            .where(session_version: nil)
                            .joins(:user)
    # debugger

    staff_count = query.count
    Rails.logger.info "🔍 Found #{staff_count} available staff users for matching"

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
      Rails.logger.info "🔄 Filtering out recent matches: #{recent_partner_ids}"
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

    Rails.logger.info "📊 Incrementing video count for user #{@user_id} in sequence #{@sequence.name}"

    # Get current video count from user
    current_video_count = @user.videos_watched_in_current_sequence || 0
    new_video_count = current_video_count + 1

    Rails.logger.info "📊 Current video count: #{current_video_count}, New count: #{new_video_count}, Threshold: #{@sequence.video_count}"

    # Update user's video count
    @user.update!(videos_watched_in_current_sequence: new_video_count)

    # Check if sequence should advance
    if new_video_count >= @sequence.video_count
      Rails.logger.info "🔄 Video count threshold reached! Advancing sequence for user #{@user_id}"
      advance_to_next_sequence
    else
      Rails.logger.info "📊 Video count updated to #{new_video_count}, sequence continues"
    end
  end

  def advance_to_next_sequence
    return unless @user && @pool

    Rails.logger.info "🔄 Advancing sequence for user #{@user_id}"

    # Find next sequence in the pool
    next_sequence = find_next_sequence_in_pool

    if next_sequence
      # Update user's sequence and reset video count
      update_user_sequence_info(next_sequence, reset_video_count: true)

      Rails.logger.info "✅ User #{@user_id} advanced to sequence #{next_sequence.name} (ID: #{next_sequence.id})"
    else
      # No more sequences, wrap back to first sequence
      first_sequence = find_first_active_sequence
      if first_sequence
        update_user_sequence_info(first_sequence, reset_video_count: true)

        Rails.logger.info "🔄 User #{@user_id} wrapped back to first sequence #{first_sequence.name} (ID: #{first_sequence.id})"
      else
        Rails.logger.warn "⚠️ No active sequences found in pool #{@pool.name}"
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
    next_sequence = active_sequences.find { |seq| seq.position > current_position }

    if next_sequence
      Rails.logger.info "🔄 Next sequence found: #{next_sequence.name} (position #{next_sequence.position})"
      next_sequence
    else
      Rails.logger.info "🔄 No next sequence found, will wrap to first"
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
      Rails.logger.info "👨‍💼 Staff user #{@user_id} should never see videos - waiting for real users only"
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

    Rails.logger.info "🎥 Video check for app user #{@user_id}: real_users_waiting=#{real_users_waiting}, staff_available=#{staff_available}, has_videos=#{has_videos}, should_show=#{should_show}"

    should_show && has_videos
  end

  def get_next_video_for_user
    return nil unless @sequence

    # Get any available video from current sequence
    videos = @sequence.videos.active
    videos.first
  end

  def create_real_user_match(other_user)
    # Use database transaction with locking to prevent race conditions
    ActiveRecord::Base.transaction do
      # Lock the other user to prevent concurrent modifications
      other_user.reload.lock!

      # Double-check availability after locking
      if other_user.status != 'waiting' || other_user.room_id.present?
        Rails.logger.warn "⚠️ User #{other_user.user_id} is no longer available after lock"
        raise ActiveRecord::Rollback, 'Other user no longer available'
      end

      # Check if we already have a room_id (in case we were matched by the other user)
      existing_room_id = @waiting_entry.room_id

      # Create room and match atomically
      room_id = existing_room_id || create_room_id

      if existing_room_id
        Rails.logger.info "🔗 Using existing room #{room_id} for users #{@user_id} and #{other_user.user_id}"
      else
        Rails.logger.info "👥 Creating new room #{room_id} for users #{@user_id} and #{other_user.user_id}"
      end

      # Generate unique session version to prevent stale signals
      session_version = generate_session_version(room_id)

      match_users_in_room(@waiting_entry, other_user, room_id, 'real_user', session_version)

      Rails.logger.info "✅ Successfully matched users #{@user_id} and #{other_user.user_id} in room #{room_id}"

      # NOW increment video count after successful match
      increment_video_count_and_check_sequence_advancement

      return {
        success: true,
        match_type: 'real_user',
        partner_id: other_user.user_id,
        room_id: room_id,
        session_version: session_version,
        is_initiator: !existing_room_id # If we already had a room, we're not the initiator
      }
    end
  rescue ActiveRecord::Rollback => e
    Rails.logger.error "❌ Failed to create real user match: #{e.message}"
    return { success: false, reason: e.message }
  rescue => e
    Rails.logger.error "❌ Unexpected error in create_real_user_match: #{e.message}"
    return { success: false, reason: 'Unexpected error occurred' }
  end

  def create_staff_match(staff_assignment)
    # Use database transaction with locking to prevent race conditions
    ActiveRecord::Base.transaction do
      # Lock the staff assignment to prevent concurrent modifications
      staff_assignment.reload.lock!

      # Verify staff is still available
      # if staff_assignment.user.status != 'online' && staff_assignment.user.status != 'in_chat'
      #   Rails.logger.warn "⚠️ Staff #{staff_assignment.user.id} is no longer available after lock"
      #   raise ActiveRecord::Rollback, 'Staff no longer available'
      # end

      # Find the staff user's waiting room entry
      staff_waiting_entry = VideoWaitingRoom.find_by(user_id: staff_assignment.user.id, status: 'waiting')
      unless staff_waiting_entry
        Rails.logger.error "❌ Staff user #{staff_assignment.user.id} has no waiting room entry - cannot create match"
        raise ActiveRecord::Rollback, 'Staff user not in waiting room'
      end

      # Check if either user already has a room_id (in case one was matched by the other)
      existing_room_id = @waiting_entry.room_id || staff_waiting_entry.room_id

      # Create room and match atomically
      room_id = existing_room_id || create_room_id

      if existing_room_id
        Rails.logger.info "🔗 Using existing room #{room_id} for app user #{@user_id} and staff user #{staff_assignment.user.id}"
      else
        Rails.logger.info "👨‍💼 Creating new room #{room_id} for app user #{@user_id} and staff user #{staff_assignment.user.id}"
      end

      # Generate unique session version to prevent stale signals
      session_version = generate_session_version(room_id)

      # Now pass both waiting room entries to ensure both get updated
      match_users_in_room(@waiting_entry, staff_waiting_entry, room_id, 'staff', session_version)

      # NOW increment video count after successful match
      increment_video_count_and_check_sequence_advancement

      return {
        success: true,
        match_type: 'staff',
        partner_id: staff_assignment.user.id,
        room_id: room_id,
        session_version: session_version,
        is_initiator: !existing_room_id # If we already had a room, we're not the initiator
      }
    end
  rescue ActiveRecord::Rollback => e
    Rails.logger.error "❌ Failed to create staff match: #{e.message}"
    return { success: false, reason: e.message }
  rescue => e
    Rails.logger.error "❌ Unexpected error in create_staff_match: #{e.message}"
    return { success: false, reason: 'Unexpected error occurred' }
  end

  def match_users_in_room(current_entry, other_entry, room_id, match_type, session_version = nil, partner_id = nil, video_id = nil)
    Rails.logger.info "🔗 Matching users in room #{room_id}"

    # Safety check: Staff users should never be matched with videos
    if @user.role == 'staff' && match_type == 'video'
      Rails.logger.error "❌ CRITICAL: Attempted to match staff user #{@user_id} with video - this should never happen!"
      raise "Staff users cannot be matched with videos"
    end

    # Determine initiator based on who created the room
    # The user who doesn't have a room_id yet becomes the initiator
    is_current_user_initiator = current_entry.room_id.nil?

    Rails.logger.info "🔗 User #{@user_id} initiator status: #{is_current_user_initiator}"

    # Update current user's entry
    current_entry.update!(
      room_id: room_id,
      partner_user_id: other_entry&.user_id,
      status: 'matched',
      is_initiator: is_current_user_initiator,
      match_type: match_type,
      video_id: video_id,
      session_version: session_version
    )

    # Update other user's entry if it exists
    if other_entry
      # The other user is NOT the initiator (they're the receiver)
      other_entry.update!(
        room_id: room_id,
        partner_user_id: @user_id,
        status: 'matched',
        is_initiator: false, # Other user is always the receiver
        match_type: match_type,
        session_version: session_version
      )
      Rails.logger.info "✅ Updated other user #{other_entry.user_id} waiting room entry (receiver)"
    end

    # Keep waiting room entries with 'matched' status for frontend detection
    Rails.logger.info "✅ Matched user #{@user_id} with #{match_type} in room #{room_id} (initiator: #{is_current_user_initiator})"
  end

  def create_room_id
    "room_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end

  def generate_session_id
    "session_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end

  def generate_session_version(room_id)
    "version_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end
end
