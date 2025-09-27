class AddVideoChatPerformanceIndexes < ActiveRecord::Migration[7.2]
  def change
    # Composite index for ultra-fast matching queries
    add_index :video_waiting_rooms,
              [:pool_id, :sequence_id, :status, :match_type, :room_id],
              name: 'idx_video_waiting_rooms_matching_optimized',
              where: "status = 'waiting' AND room_id IS NULL"

    # Index for partner matching
    add_index :video_waiting_rooms,
              [:user_id, :status, :room_id],
              name: 'idx_video_waiting_rooms_user_status'

    # Index for session cleanup
    add_index :video_waiting_rooms,
              [:room_id, :status],
              name: 'idx_video_waiting_rooms_room_cleanup'

    # Index for recent partners query optimization
    add_index :video_chat_sessions,
              [:user_id, :created_at, :status, :partner_user_id],
              name: 'idx_video_chat_sessions_recent_partners'

    # Index for active sessions count
    add_index :video_chat_sessions,
              [:status, :created_at],
              name: 'idx_video_chat_sessions_active'
  end
end
