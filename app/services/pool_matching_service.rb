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

      # Use the new structured matching approach with proper priority
      match_result = find_match_with_priority_order

      if match_result[:success]
        Rails.logger.info "✅ Match successful: #{match_result[:match_type]}"
        return match_result
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

  # NEW: Structured matching with proper priority order
  def find_match_with_priority_order
    Rails.logger.info "🎯 Using structured priority matching for user #{@user_id}"

    # PRIORITY 1: No repeats (avoid recent connections)
    Rails.logger.info "🔍 Priority 1: Trying matches without repeats..."

    # 1.1: Real user match (no repeats)
    if @user.role != 'staff'
      real_user_no_repeat = find_real_user_match_no_repeats
      if real_user_no_repeat[:success]
        Rails.logger.info "✅ Priority 1.1: Real user match (no repeats) successful!"
        return real_user_no_repeat
      end
    end

    # 1.2: Staff match (no repeats) - only for app users
    if @user.role != 'staff'
      staff_no_repeat = find_staff_match_no_repeats
      if staff_no_repeat[:success]
        Rails.logger.info "✅ Priority 1.2: Staff match (no repeats) successful!"
        return staff_no_repeat
      end
    end

    # 1.3: Video match (no repeats) - only for app users
    if @user.role != 'staff'
      video_no_repeat = find_video_match_no_repeats
      if video_no_repeat[:success]
        Rails.logger.info "✅ Priority 1.3: Video match (no repeats) successful!"
        return video_no_repeat
      end
    end

    # PRIORITY 2: With repeats (fallback when no fresh matches)
    Rails.logger.info "🔍 Priority 2: Trying matches with repeats (fallback)..."

    # 2.1: Real user match (with repeats)
    if @user.role != 'staff'
      real_user_with_repeat = find_real_user_match_with_repeats
      if real_user_with_repeat[:success]
        Rails.logger.info "✅ Priority 2.1: Real user match (with repeats) successful!"
        return real_user_with_repeat
      end
    end

    # 2.2: Staff match (with repeats) - only for app users
    if @user.role != 'staff'
      staff_with_repeat = find_staff_match_with_repeats
      if staff_with_repeat[:success]
        Rails.logger.info "✅ Priority 2.2: Staff match (with repeats) successful!"
        return staff_with_repeat
      end
    end

    # 2.3: Video match (with repeats) - only for app users
    if @user.role != 'staff'
      video_with_repeat = find_video_match_with_repeats
      if video_with_repeat[:success]
        Rails.logger.info "✅ Priority 2.3: Video match (with repeats) successful!"
        return video_with_repeat
      end
    end

    Rails.logger.info "❌ No matches available in any priority level"
    { success: false, reason: 'No matches available in any priority level' }
  end

  # Find next match when user swipes or disconnects
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
      Rails.logger.info "🔄 No real user match found for app user #{@user_id}, checking for staff/video fallback..."

      # Try staff match as fallback
      staff_match = find_staff_match
      if staff_match[:success]
        Rails.logger.info "✅ Staff match fallback successful for app user #{@user_id}"
        return staff_match
      end

      # Try video match as final fallback
      video_match = find_video_match
      if video_match[:success]
        Rails.logger.info "✅ Video match fallback successful for app user #{@user_id}"
        return video_match
      end
    end

    match_result
  end

  # Handle disconnection when user swipes from a shared room
  def handle_room_disconnection
    return unless @waiting_entry&.room_id.present?

    room_id = @waiting_entry.room_id
    Rails.logger.info "🔄 User #{@user_id} swiping from room #{room_id}, handling disconnection"

    # Use database transaction to prevent race conditions
    ActiveRecord::Base.transaction do
      # Find all users in this room (without locking for count)
      users_in_room = VideoWaitingRoom.where(room_id: room_id)
      user_count = users_in_room.count

      if user_count > 1
        # Now lock the actual records we'll be updating
        users_in_room = users_in_room.lock
        Rails.logger.info "🔄 Found #{user_count} users in room #{room_id}, disconnecting all"

        # Disconnect all users from this room
        users_in_room.each do |user_entry|
          next if user_entry.user_id == @user_id # Skip current user, handle separately

          Rails.logger.info "🔄 Disconnecting user #{user_entry.user_id} from room #{room_id}"

          # Reset partner's entry and set them back to waiting
          reset_user_to_waiting_state(user_entry)

          # IMPORTANT: Trigger immediate match finding to prevent user being stuck
          # This ensures they get a new match right away instead of waiting
          Rails.logger.info "🔄 Triggering immediate match for disconnected user #{user_entry.user_id}"
          trigger_new_match_for_user(user_entry.user_id)
        end
      end

      # Clean up current user's entry
      reset_user_to_waiting_state(@waiting_entry)
      Rails.logger.info "✅ Current user #{@user_id} reset to waiting status"

      # Mark this room as recently disconnected to prevent immediate reuse
      mark_room_as_recently_disconnected(room_id)
    end

    Rails.logger.info "✅ Room #{room_id} disconnection completed for user #{@user_id}"
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
    Rails.logger.info "🧹 Checking for stale room assignments for user #{@user_id}"

    # Find any waiting entries that might have stale room assignments
    stale_entries = VideoWaitingRoom.where(
      user_id: @user_id,
      status: 'waiting'
    ).where.not(room_id: nil)

    if stale_entries.any?
      Rails.logger.info "🧹 Found #{stale_entries.count} stale room assignments for user #{@user_id}"

      stale_entries.each do |entry|
        room_id = entry.room_id
        Rails.logger.info "🧹 Cleaning up stale room #{room_id} for user #{@user_id}"

        # Check if other users are still in this room
        other_users_in_room = VideoWaitingRoom.where(room_id: room_id)
                                             .where.not(user_id: @user_id)

        if other_users_in_room.any?
          Rails.logger.info "🧹 Found #{other_users_in_room.count} other users still in stale room #{room_id}"

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
            Rails.logger.info "🧹 Cleaned up user #{other_entry.user_id} from stale room #{room_id}"
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
        Rails.logger.info "🧹 Cleaned up stale room #{room_id} for user #{@user_id}"
      end
    else
      Rails.logger.info "🧹 No stale room assignments found for user #{@user_id}"
    end
  end

  # Ensure proper cleanup when user swipes
  def ensure_partner_cleanup_on_swipe
    return unless @waiting_entry&.room_id.present?

    room_id = @waiting_entry.room_id
    Rails.logger.info "🧹 Ensuring partner cleanup for user #{@user_id} in room #{room_id}"

    # Find partner in the same room
    partner_entry = VideoWaitingRoom.where(room_id: room_id)
                                   .where.not(user_id: @user_id)
                                   .first

    if partner_entry
      Rails.logger.info "🧹 Found partner #{partner_entry.user_id} in room #{room_id}, ensuring cleanup"

      # Reset partner's entry
      if partner_entry.user.role == 'staff'
        partner_entry.update!(
          room_id: nil,
          partner_user_id: nil,
          status: 'waiting',
          match_type: 'staff',
          session_version: nil
        )
        Rails.logger.info "✅ Partner staff user #{partner_entry.user_id} properly reset"
      else
        partner_entry.update!(
          room_id: nil,
          partner_user_id: nil,
          status: 'waiting',
          match_type: 'real_user',
          session_version: nil
        )
        Rails.logger.info "✅ Partner real user #{partner_entry.user_id} properly reset"
      end

      # Trigger new match for partner
      trigger_new_match_for_user(partner_entry.user_id)
    else
      Rails.logger.info "🧹 No partner found in room #{room_id}, cleanup not needed"
    end
  end

  # Mark room as recently disconnected to prevent immediate reuse
  def mark_room_as_recently_disconnected(room_id)
    # Store the room ID in Redis or a similar cache with a TTL
    # This prevents the same room from being reused immediately
    Rails.logger.info "🚫 Marking room #{room_id} as recently disconnected (preventing reuse)"

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
      Rails.logger.info "🚫 Room #{room_id} was recently disconnected (global cache)"
      return true
    end

    # Fallback to local tracking
    if @recently_disconnected_rooms&.include?(room_id)
      Rails.logger.info "🚫 Room #{room_id} was recently disconnected (local tracking)"
      return true
    end

    false
  end

  # Handle staff disconnection properly
  def handle_staff_disconnection
    return unless @user.role == 'staff'

    Rails.logger.info "👨‍💼 Staff user #{@user_id} disconnected, ensuring proper state reset..."

    # Staff users should always be available for new real user matches
    @waiting_entry.update!(
      room_id: nil,
      partner_user_id: nil,
      status: 'waiting',
      match_type: 'staff',
      session_version: nil
    )

    Rails.logger.info "✅ Staff user #{@user_id} reset and ready for new real user matches"
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

    Rails.logger.info "🔄 Filtering out recently disconnected users: #{recent_room_users}"
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
    Rails.logger.info "🔍 Building staff query for pool #{@pool.id}, sequence #{@sequence.id}"

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

  def get_next_video_for_user_no_repeats
    return nil unless @sequence

    # Get any available video from current sequence
    videos = @sequence.videos.active
    videos.first
  end

  def get_next_video_for_user_with_repeats
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

      # ALWAYS create a new room ID to prevent WebRTC m-lines conflicts
      # This ensures fresh WebRTC context for each connection
      room_id = create_room_id
      Rails.logger.info "👥 Creating new room #{room_id} for users #{@user_id} and #{other_user.user_id} (no room reuse to prevent WebRTC conflicts)"

      # Generate unique session version to prevent stale signals
      session_version = generate_session_version(room_id)
      match_users_in_room(@waiting_entry, other_user, room_id, 'real_user', session_version)

      Rails.logger.info "✅ Successfully matched users #{@user_id} and #{other_user.user_id} in room #{room_id}"

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

      # ALWAYS create a new room ID to prevent WebRTC m-lines conflicts
      # This ensures fresh WebRTC context for each connection
      room_id = create_room_id
      Rails.logger.info "👨‍💼 Creating new room #{room_id} for app user #{@user_id} and staff user #{staff_assignment.user.id} (no room reuse to prevent WebRTC conflicts)"

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

    # Determine initiator based on user ID (lower ID becomes initiator for consistency)
    # This ensures consistent initiator assignment for each new connection
    is_current_user_initiator = @user_id < (other_entry&.user_id || 999999)

    Rails.logger.info "🔗 User #{@user_id} initiator status: #{is_current_user_initiator} (based on user ID comparison)"

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
      Rails.logger.info "✅ Updated other user #{other_entry.user_id} entry (initiator: #{!is_current_user_initiator})"
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
    # Use room_id hash + timestamp + random to ensure uniqueness even for simultaneous matches
    # This prevents both users from getting the same session version when matched at the same time
    room_hash = Digest::MD5.hexdigest(room_id)[0..7]
    "version_#{Time.current.to_i}_#{room_hash}_#{SecureRandom.hex(4)}"
  end

  # NEW: Real user matching methods
  def find_real_user_match_no_repeats
    Rails.logger.info "👥 Looking for real user match (no repeats) in pool #{@pool.name}, sequence #{@sequence.name}"

    base_query = build_real_user_query_no_repeats
    match_result = find_match_with_gender_preference_logic(base_query, 'real_user')

    if match_result[:success]
      return create_real_user_match(match_result[:match])
    end

    { success: false, reason: 'No real users available (no repeats)' }
  end

  def find_real_user_match_with_repeats
    Rails.logger.info "👥 Looking for real user match (with repeats) in pool #{@pool.name}, sequence #{@sequence.name}"

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

    Rails.logger.info "👨‍💼 Looking for staff match (no repeats) for app user #{@user_id}"

    base_query = build_staff_query_no_repeats
    match_result = find_match_with_gender_preference_logic(base_query, 'staff')

    if match_result[:success]
      return create_staff_match(match_result[:match])
    end

    { success: false, reason: 'No staff available (no repeats)' }
  end

  def find_staff_match_with_repeats
    return { success: false, reason: 'Staff users cannot match with other staff' } if @user.role == 'staff'

    Rails.logger.info "👨‍💼 Looking for staff match (with repeats) for app user #{@user_id}"

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

    Rails.logger.info "🎥 Looking for video match (no repeats) for app user #{@user_id}"

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

    Rails.logger.info "🎥 Looking for video match (with repeats) for app user #{@user_id}"

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
    Rails.logger.info "🎥 Creating room #{room_id} for video #{available_video.id}"
    session_version = generate_session_version(room_id)

    match_users_in_room(@waiting_entry, nil, room_id, 'video', session_version, nil, available_video.id)

    Rails.logger.info "✅ User #{@user_id} matched with video #{available_video.id} in sequence #{@sequence.name}"

    # Increment video count after successful match
    increment_video_count_after_match

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

    Rails.logger.info "🔄 Repeat matching: Found #{recently_matched_users.count} recently matched users: #{recently_matched_users}"

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

      Rails.logger.info "🔄 Repeat matching: Prioritizing users by match order: #{recently_matched_users}"
    else
      # No recent matches, use default ordering
      base_query = base_query.joins(:user).order(:joined_at)
      Rails.logger.info "🔄 Repeat matching: No recent matches, using default ordering"
    end

    base_query
  end

  def build_staff_query_no_repeats
    # Staff can only be in ONE session at a time
    # Check if staff user is already in an active session
    Rails.logger.info "🔍 Building staff query (no repeats) for pool #{@pool.id}, sequence #{@sequence.id}"

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
    Rails.logger.info "🔍 Found #{staff_count} available staff users for matching (no repeats)"

    query
  end

  def build_staff_query_with_repeats
    # Staff can only be in ONE session at a time
    # Check if staff user is already in an active session
    Rails.logger.info "🔍 Building staff query (with repeats) for pool #{@pool.id}, sequence #{@sequence.id}"

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
    Rails.logger.info "🔍 Found #{staff_count} available staff users for matching (with repeats)"

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
      Rails.logger.info "🔄 Video count threshold reached! Advancing sequence for user #{@user_id}"
      advance_to_next_sequence
    else
      Rails.logger.info "📊 Current video count: #{current_video_count}, threshold: #{@sequence.video_count}, sequence continues"
    end
  end

  # Increment video count after successful match completion
  def increment_video_count_after_match
    return unless @user && @sequence

    Rails.logger.info "📊 Incrementing video count for user #{@user_id} in sequence #{@sequence.name}"

    # Get current video count from user
    current_video_count = @user.videos_watched_in_current_sequence || 0
    new_video_count = current_video_count + 1

    Rails.logger.info "📊 Current video count: #{current_video_count}, New count: #{new_video_count}, Threshold: #{@sequence.video_count}"

    # Update user's video count
    @user.update!(videos_watched_in_current_sequence: new_video_count)

    Rails.logger.info "📊 Video count updated to #{new_video_count} for sequence #{@sequence.name}"
  end
end
