class PoolMatchingService
  include ActiveSupport::Configurable

  # Configuration
  config_accessor :staff_fallback_delay, :max_video_duration, :sequence_group_size
  config.staff_fallback_delay = 3.seconds
  config.max_video_duration = 30.seconds
  config.sequence_group_size = 10

  def initialize(user_id)
    @user_id = user_id
    @user = User.find_by(id: user_id)
    @pool = @user&.pool
    @sequence = @user&.pool&.sequences&.active&.ordered&.first
    @waiting_entry = VideoWaitingRoom.find_by(user_id: user_id)
  end

  # TEMPORARY: Force real user matching for testing
  def force_real_user_match_for_testing
    Rails.logger.info "🧪 FORCE TESTING: Attempting to force real user match"

    # Find any other user in the same pool and sequence
    other_user = VideoWaitingRoom.waiting
                                 .real_users_available
                                 .by_pool(@pool.id)
                                 .by_sequence(@sequence.id)
                                 .where.not(user_id: @user_id)
                                 .first

    if other_user
      Rails.logger.info "🧪 FORCE TESTING: Found user #{other_user.user_id} for forced match"

      # Create room and force match
      room_id = create_room_id
      match_users_in_room(@waiting_entry, other_user, room_id, 'real_user')

      {
        success: true,
        match_type: 'real_user',
        partner_id: other_user.user_id,
        room_id: room_id,
        is_initiator: true
      }
    else
      Rails.logger.info "🧪 FORCE TESTING: No other users available for forced match"
      { success: false, reason: 'No other users available for forced match' }
    end
  end

  # Main matching method - tries to find the best match
  def find_match
    Rails.logger.info "🔍 Finding match for user #{@user_id} in pool #{@pool&.name} (ID: #{@pool&.id}), sequence #{@sequence&.name} (ID: #{@sequence&.id})"

    # Debug: Show current pool state
    debug_pool_state

    # Check if current user is currently watching a video
    if @waiting_entry&.match_type == 'video' && @waiting_entry&.room_id.present?
      Rails.logger.info "🔄 Current user #{@user_id} is watching a video, handling video user swipe..."
      return handle_video_user_swipe
    end

    # Step 0: Proactively connect video users if possible
    Rails.logger.info "🔍 Step 0: Checking for proactive video user connections..."
    proactive_connection = connect_video_users_proactively
    if proactive_connection[:success]
      Rails.logger.info "✅ Proactive video connection successful!"
      Rails.logger.info "🔍 Returning room_id: #{proactive_connection[:room_id]}"
      return proactive_connection
    end

    # Step 1: Try to match with another real user from same pool
    Rails.logger.info "🔍 Step 1: Trying real user match..."
    real_user_match = find_real_user_match
    if real_user_match[:success]
      Rails.logger.info "✅ Real user match successful!"
      Rails.logger.info "🔍 Returning room_id: #{real_user_match[:room_id]}"
      return real_user_match
    end

    # Step 1.5: Try to connect with a user who is currently watching a video
    Rails.logger.info "🔍 Step 1.5: Trying to connect with video user..."
    video_connection = connect_real_user_with_video_user
    if video_connection[:success]
      Rails.logger.info "✅ Video user connection successful!"
      Rails.logger.info "🔍 Returning room_id: #{video_connection[:room_id]}"
      return video_connection
    end

    # Step 2: Try to match with staff
    Rails.logger.info "🔍 Step 2: Trying staff match..."
    staff_match = find_staff_match
    if staff_match[:success]
      Rails.logger.info "✅ Staff match successful!"
      Rails.logger.info "🔍 Returning room_id: #{staff_match[:room_id]}"
      return staff_match
    end

    # Step 3: Check if we should show video next
    Rails.logger.info "🔍 Step 3: Checking video availability..."
    Rails.logger.info "🔍 Should show video next? #{should_show_video_next?}"
    Rails.logger.info "🔍 Sequence videos count: #{@sequence.videos.active.count}"

    video_match = find_video_match
    if video_match[:success]
      Rails.logger.info "✅ Video match successful!"
      Rails.logger.info "🔍 Returning room_id: #{video_match[:room_id]}"
      return video_match
    end

    Rails.logger.info "❌ No match found for user #{@user_id}"
    { success: false, reason: 'No matches available' }
  end

  # Find next match when user swipes or disconnects
  def find_next_match
    return { error: 'User not found' } unless @user

    # Move to next sequence if needed
    advance_sequence_if_needed

    # Try to find next match
    find_match
  end

  # Create a session for tracking
  def create_session(match_data)
    return nil unless match_data[:success]

    session_attributes = {
      user_id: @user_id,
      pool_id: @pool&.id,
      sequence_id: @sequence&.id,
      session_id: generate_session_id,
      started_at: Time.current
    }

    case match_data[:match_type]
    when 'real_user'
      session_attributes.merge!(
        session_type: 'user_to_user',
        partner_user_id: match_data[:partner_id],
        status: 'active'
      )
    when 'staff'
      session_attributes.merge!(
        session_type: 'user_to_staff',
        staff_user_id: match_data[:partner_id],
        status: 'active'
      )
    when 'video'
      session_attributes.merge!(
        session_type: 'user_to_video',
        video_id: match_data[:video_id],
        status: 'active'
      )
    end

    VideoChatSession.create!(session_attributes)
  end

  # Method to handle user swiping while watching a video
  def handle_video_user_swipe
    Rails.logger.info "🔄 Handling swipe for video user #{@user_id}..."

    # First, try to connect with other video users
    video_connection = connect_real_user_with_video_user
    if video_connection[:success]
      Rails.logger.info "✅ Video user connected with another video user!"
      return video_connection
    end

    # If no video users available, try to connect with real users
    real_user_match = find_real_user_match
    if real_user_match[:success]
      Rails.logger.info "✅ Video user connected with real user!"
      return real_user_match
    end

    # If no real users available, try staff
    staff_match = find_staff_match
    if staff_match[:success]
      Rails.logger.info "✅ Video user connected with staff!"
      return staff_match
    end

    # If nothing else available, show next video
    Rails.logger.info "🔄 No connections available, showing next video..."
    video_match = find_video_match
    if video_match[:success]
      Rails.logger.info "✅ Next video found for video user!"
      return video_match
    end

    Rails.logger.info "❌ No matches available for video user swipe"
    { success: false, reason: 'No matches available for video user' }
  end

  # Debug method to show current pool state
  def debug_pool_state
    Rails.logger.info "🔍 === POOL STATE DEBUG ==="
    Rails.logger.info "🔍 Pool: #{@pool&.name} (ID: #{@pool&.id})"
    Rails.logger.info "🔍 Sequence: #{@sequence&.name} (ID: #{@sequence&.id})"
    Rails.logger.info "🔍 Current User: #{@user_id}"

    # All users in this pool/sequence
    all_users = VideoWaitingRoom.where(pool_id: @pool.id, sequence_id: @sequence.id)
    Rails.logger.info "🔍 Total users in pool/sequence: #{all_users.count}"

    all_users.each do |user|
      Rails.logger.info "🔍 User #{user.user_id}: status=#{user.status}, match_type=#{user.match_type}, room_id=#{user.room_id}, video_id=#{user.video_id}"
    end

    # Waiting users
    waiting_users = VideoWaitingRoom.waiting.where(pool_id: @pool.id, sequence_id: @sequence.id)
    Rails.logger.info "🔍 Waiting users: #{waiting_users.count}"

    # Matched video users
    video_users = VideoWaitingRoom.where(pool_id: @pool.id, sequence_id: @sequence.id, match_type: 'video', status: 'matched')
    Rails.logger.info "🔍 Matched video users: #{video_users.count}"

    # Real user waiting
    real_users_waiting = VideoWaitingRoom.waiting.where(pool_id: @pool.id, sequence_id: @sequence.id, match_type: 'real_user')
    Rails.logger.info "🔍 Real users waiting: #{real_users_waiting.count}"

    Rails.logger.info "🔍 === END POOL STATE DEBUG ==="
  end

  private

  # Helper method to check if a user is available for matching
  def user_available_for_matching?(waiting_entry)
    return false unless waiting_entry
    return false unless waiting_entry.status == 'waiting'
    return false if waiting_entry.room_id.present?
    return false unless waiting_entry.match_type == 'real_user'
    return false unless waiting_entry.pool_id == @pool.id
    return false unless waiting_entry.sequence_id == @sequence.id

    true
  end

  # Method to connect real users with video users automatically
  def connect_real_user_with_video_user
    Rails.logger.info "🔗 Attempting to connect real user with video user..."

    # First, check if there are multiple video users who could be connected together
    # Video users have status: 'matched' because they're already matched with videos
    video_users = VideoWaitingRoom.where(pool_id: @pool.id)
                                 .where(sequence_id: @sequence.id)
                                 .where(match_type: 'video')
                                 .where.not(room_id: nil)
                                 .where(status: 'matched')

    Rails.logger.info "🔗 Found #{video_users.count} video users in pool #{@pool.name}, sequence #{@sequence.name}"
    # If there are multiple video users, prioritize connecting them together
    if video_users.count > 1
      Rails.logger.info "🔗 Multiple video users found, prioritizing video-to-video connections"

      # Find two video users who could be connected
      first_video_user = video_users.first
      second_video_user = video_users.where.not(user_id: first_video_user.user_id).first

      if first_video_user && second_video_user
        Rails.logger.info "🔗 Connecting video users #{first_video_user.user_id} and #{second_video_user.user_id}"

        # Create a new room for real user connection between video users
        new_room_id = create_room_id
        Rails.logger.info "🔗 Creating new room #{new_room_id} for video user connection"

        # Match the two video users together
        match_users_in_room(first_video_user, second_video_user, new_room_id, 'real_user')

        Rails.logger.info "✅ Successfully connected video users #{first_video_user.user_id} and #{second_video_user.user_id} in room #{new_room_id}"

        return {
          success: true,
          match_type: 'real_user',
          partner_id: second_video_user.user_id,
          room_id: new_room_id,
          is_initiator: true,
          connected_from_video: true
        }
      end
    end

    # If no video-to-video connection possible, try to connect current user with a video user
    if user_available_for_matching?(@waiting_entry)
      video_user = video_users.first

      if video_user
        Rails.logger.info "🔗 Found video user #{video_user.user_id} in room #{video_user.room_id}"
        Rails.logger.info "🔗 Current user #{@user_id} is available for real user matching"

        # Create a new room for real user connection
        new_room_id = create_room_id
        Rails.logger.info "🔗 Creating new room #{new_room_id} for real user connection"

        # Match the current user with the video user
        match_users_in_room(@waiting_entry, video_user, new_room_id, 'real_user')

        Rails.logger.info "✅ Successfully connected real user #{@user_id} with video user #{video_user.user_id} in room #{new_room_id}"

        return {
          success: true,
          match_type: 'real_user',
          partner_id: video_user.user_id,
          room_id: new_room_id,
          is_initiator: true,
          connected_from_video: true
        }
      end
    end

    Rails.logger.info "🔗 No video user connections possible"
    { success: false, reason: 'No video user connections possible' }
  end

  # Method to proactively connect video users when they join
  def connect_video_users_proactively
    Rails.logger.info "🔗 Checking for proactive video user connections..."

    # Find all video users in the same pool and sequence
    # Video users have status: 'matched' because they're already matched with videos
    video_users = VideoWaitingRoom.where(pool_id: @pool.id)
                                 .where(sequence_id: @sequence.id)
                                 .where(match_type: 'video')
                                 .where.not(room_id: nil)
                                 .where(status: 'matched')

    Rails.logger.info "🔗 Found #{video_users.count} video users for proactive connection"

    # Debug: Show all video users found
    video_users.each do |user|
      Rails.logger.info "🔗 Video user #{user.user_id}: room_id=#{user.room_id}, status=#{user.status}"
    end

    # If there are 2 or more video users, connect them together
    if video_users.count >= 2
      Rails.logger.info "🔗 Multiple video users found, connecting them together"

      # Take the first two video users and connect them
      first_video_user = video_users.first
      second_video_user = video_users.where.not(user_id: first_video_user.user_id).first

      Rails.logger.info "🔗 First video user: #{first_video_user.user_id}, Second video user: #{second_video_user&.user_id}"

      if first_video_user && second_video_user
        # Create a new room for the connection
        new_room_id = create_room_id
        Rails.logger.info "🔗 Creating proactive room #{new_room_id} for video users #{first_video_user.user_id} and #{second_video_user.user_id}"

        # Connect the two video users
        match_users_in_room(first_video_user, second_video_user, new_room_id, 'real_user')

        # Verify the match in database
        verify_match_in_database(new_room_id)

        Rails.logger.info "✅ Proactively connected video users #{first_video_user.user_id} and #{second_video_user.user_id} in room #{new_room_id}"

        return {
          success: true,
          match_type: 'real_user',
          partner_id: second_video_user.user_id,
          room_id: new_room_id,
          is_initiator: true,
          connected_proactively: true
        }
      end
    end

    # If there's exactly 1 video user and current user is available, connect them
    if video_users.count == 1 && user_available_for_matching?(@waiting_entry)
      Rails.logger.info "🔗 Single video user found, connecting with current user"

      video_user = video_users.first
      new_room_id = create_room_id
      Rails.logger.info "🔗 Creating proactive room #{new_room_id} for video user #{video_user.user_id} and current user #{@user_id}"

      # Connect current user with video user
      match_users_in_room(@waiting_entry, video_user, new_room_id, 'real_user')

      # Verify the match in database
      verify_match_in_database(new_room_id)

      Rails.logger.info "✅ Proactively connected video user #{video_user.user_id} with current user #{@user_id} in room #{new_room_id}"

      return {
        success: true,
        match_type: 'real_user',
        partner_id: video_user.user_id,
        room_id: new_room_id,
        is_initiator: true,
        connected_proactively: true
      }
    end

    Rails.logger.info "🔗 No proactive video connections possible"
    { success: false, reason: 'No proactive video connections possible' }
  end

  def find_real_user_match
    Rails.logger.info "👥 Looking for real user match in pool #{@pool.name}, sequence #{@sequence.name}"

    # Find another real user from the same pool and sequence who is still waiting
    other_user = VideoWaitingRoom.waiting
                                 .where.not(user_id: @user_id)
                                 .where(pool_id: @pool.id)
                                 .where(sequence_id: @sequence.id)
                                 .where(match_type: 'real_user')
                                 .where(room_id: nil)
                                 .order(:joined_at)
                                 .first

    if other_user
      Rails.logger.info "👥 Found potential match: user #{other_user.user_id}"

      # Use helper method to verify availability
      unless user_available_for_matching?(other_user)
        Rails.logger.warn "⚠️ User #{other_user.user_id} is not available for matching"
        return { success: false, reason: 'Other user not available for matching' }
      end

      # Double-check that the other user is still available
      other_user.reload
      if other_user.status != 'waiting' || other_user.room_id.present?
        Rails.logger.warn "⚠️ User #{other_user.user_id} is no longer available (status: #{other_user.status}, room: #{other_user.room_id})"
        return { success: false, reason: 'Other user no longer available' }
      end

      # Create room and match
      room_id = create_room_id
      Rails.logger.info "👥 Creating room #{room_id} for users #{@user_id} and #{other_user.user_id}"

      match_users_in_room(@waiting_entry, other_user, room_id, 'real_user')

      # Verify the match in database
      verify_match_in_database(room_id)

      Rails.logger.info "✅ Successfully matched users #{@user_id} and #{other_user.user_id} in room #{room_id}"

      {
        success: true,
        match_type: 'real_user',
        partner_id: other_user.user_id,
        room_id: room_id,
        is_initiator: true
      }
    else
      Rails.logger.info "❌ No other users available for matching in pool #{@pool.name}, sequence #{@sequence.name}"
      return { success: false, reason: 'No other users available' }
    end
  end

  def find_staff_match
    # Find available staff from the same pool and sequence
    available_staff = StaffAssignment.active
                                    .by_pool(@pool.id)
                                    .by_sequence(@sequence.id)
                                    .joins(:user)
                                    .where(users: { status: [:online, :in_chat] })
                                    .where.not(users: { id: @user_id })
                                    .first

    return { success: false } unless available_staff&.user

    # Create room and match with staff
    room_id = create_room_id
    match_users_in_room(@waiting_entry, nil, room_id, 'staff', available_staff.user.id)

    {
      success: true,
      match_type: 'staff',
      partner_id: available_staff.user.id,
      room_id: room_id,
      is_initiator: true
    }
  end

  def find_video_match
    Rails.logger.info "🎥 Starting video match process..."

    # Check if user should see video next based on sequence logic
    should_show = should_show_video_next?
    return { success: false, reason: 'should_show_video_next returned false' } unless should_show

    # Double-check: Ensure no real users are available before proceeding with video
    real_users_waiting = VideoWaitingRoom.waiting
                                        .where(pool_id: @pool.id)
                                        .where(sequence_id: @sequence.id)
                                        .where(match_type: 'real_user')
                                        .where.not(user_id: @user_id)
                                        .count

    if real_users_waiting > 0
      Rails.logger.warn "⚠️ Video match blocked: Found #{real_users_waiting} real users waiting"
      return { success: false, reason: 'Real users available, video match blocked' }
    end

    # Get next available video user hasn't seen
    available_video = get_next_video_for_user
    return { success: false, reason: 'No available video found' } unless available_video

    # Create room and match with video
    room_id = create_room_id
    Rails.logger.info "🎥 Creating room #{room_id} for video #{available_video.id}"

    match_users_in_room(@waiting_entry, nil, room_id, 'video', nil, available_video.id)

    Rails.logger.info "✅ User #{@user_id} matched with video #{available_video.id} in sequence #{@sequence.name}"

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
      is_initiator: true
    }
  end

  def should_try_staff_fallback?
    return false unless @waiting_entry

    # Check if user has been waiting long enough for staff fallback
    time_waiting = Time.current - @waiting_entry.joined_at
    time_waiting >= config.staff_fallback_delay
  end

  def advance_sequence_if_needed
    return unless @sequence

    # Check if user has completed enough interactions in current sequence
    completed_sessions = VideoChatSession.where(
      user_id: @user_id,
      sequence_id: @sequence.id,
      status: ['completed', 'disconnected']
    ).count

    # If user has completed enough sessions, move to next sequence
    if completed_sessions >= config.sequence_group_size
      next_seq = @user.next_sequence(@sequence.position)
      if next_seq
        @sequence = next_seq
        @waiting_entry&.update!(sequence_id: next_seq.id)
        Rails.logger.info "🔄 User #{@user_id} advanced to sequence #{next_seq.name} (position #{next_seq.position})"
      end
    end
  end

  # Get next available video for user in current sequence
  def get_next_video_for_user
    Rails.logger.info "🎥 Getting next video for user #{@user_id} in sequence #{@sequence&.name}"
    return nil unless @sequence

    # Get any available video from current sequence (simplified)
    videos = @sequence.videos.active
    Rails.logger.info "🎥 Active videos in sequence: #{videos.count} videos"

    first_video = videos.first
    Rails.logger.info "🎥 First available video: #{first_video&.id} (#{first_video&.name})"
    first_video
  end

  # Check if user should see video next
  def should_show_video_next?
    Rails.logger.info "🎥 Checking if should show video next for user #{@user_id}"
    return false unless @sequence

    # Check if there are any real users waiting
    real_users_waiting = VideoWaitingRoom.waiting
                                        .where(pool_id: @pool.id)
                                        .where(sequence_id: @sequence.id)
                                        .where(match_type: 'real_user')
                                        .where.not(user_id: @user_id)
                                        .count

    Rails.logger.info "🎥 Real users waiting: #{real_users_waiting}"

    # Check if there are any staff available
    staff_available = VideoWaitingRoom.waiting
                                     .where(pool_id: @pool.id)
                                     .where(sequence_id: @sequence.id)
                                     .where(match_type: 'staff')
                                     .count

    Rails.logger.info "🎥 Staff available: #{staff_available}"

    # Check if there are any video users that could be connected
    video_users = VideoWaitingRoom.where(pool_id: @pool.id)
                                 .where(sequence_id: @sequence.id)
                                 .where(match_type: 'video')
                                 .where.not(room_id: nil)
                                 .where(status: 'matched')
                                 .count

    Rails.logger.info "🎥 Video users available for connection: #{video_users}"

    # Only show video if no real users, staff, or video connections are possible
    should_show = real_users_waiting == 0 && staff_available == 0 && video_users < 2

    Rails.logger.info "🎥 Should show video next? #{should_show} (no real users: #{real_users_waiting == 0}, no staff: #{staff_available == 0}, insufficient video users: #{video_users < 2})"

    # Also check if there are actually videos available
    has_videos = @sequence.videos.active.exists?
    Rails.logger.info "🎥 Has active videos: #{has_videos}"

    should_show && has_videos
  end

  def create_room_id
    "room_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end

  # Verify database state after matching
  def verify_match_in_database(room_id)
    Rails.logger.info "🔍 Verifying match in database for room: #{room_id}"

    # Find all users in this room
    users_in_room = VideoWaitingRoom.where(room_id: room_id)
    Rails.logger.info "🔍 Users in room #{room_id}: #{users_in_room.count}"

    users_in_room.each do |user|
      Rails.logger.info "🔍 User #{user.user_id}: room_id=#{user.room_id}, status=#{user.status}, match_type=#{user.match_type}"
    end

    # Verify all users have the same room_id
    if users_in_room.count >= 2
      room_ids = users_in_room.pluck(:room_id).uniq
      if room_ids.count == 1 && room_ids.first == room_id
        Rails.logger.info "✅ Database verification successful: All users have room_id #{room_id}"
      else
        Rails.logger.error "❌ Database verification failed: Users have different room_ids: #{room_ids}"
      end
    end
  end

  def match_users_in_room(current_entry, other_entry, room_id, match_type, partner_id = nil, video_id = nil)
    Rails.logger.info "🔗 match_users_in_room called:"
    Rails.logger.info "🔗 - Current user: #{@user_id}, Entry: #{current_entry&.user_id}"
    Rails.logger.info "🔗 - Other user: #{other_entry&.user_id if other_entry}"
    Rails.logger.info "🔗 - Room ID: #{room_id}"
    Rails.logger.info "🔗 - Match type: #{match_type}"

    # Update current user's entry
    current_entry.update!(
      room_id: room_id,
      partner_user_id: other_entry&.user_id,
      status: 'matched',
      is_initiator: true,
      match_type: match_type,
      video_id: video_id
    )

    Rails.logger.info "✅ Updated current user #{@user_id} with room_id: #{room_id}"

    # Update other user's entry if it exists
    if other_entry
      other_entry.update!(
        room_id: room_id,
        partner_user_id: @user_id,
        status: 'matched',
        is_initiator: false,
        match_type: match_type
      )

      Rails.logger.info "✅ Updated other user #{other_entry.user_id} with room_id: #{room_id}"
    end

    Rails.logger.info "✅ Matched user #{@user_id} with #{match_type} in room #{room_id}"
  end

  def generate_session_id
    "session_#{Time.current.to_i}_#{SecureRandom.hex(4)}"
  end
end
