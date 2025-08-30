class AddPoolAndSequenceToVideoWaitingRooms < ActiveRecord::Migration[7.2]
  def change
    add_reference :video_waiting_rooms, :pool, null: true, foreign_key: true
    add_reference :video_waiting_rooms, :sequence, null: true, foreign_key: true
    add_column :video_waiting_rooms, :match_type, :string, null: false, default: 'real_user'
    add_column :video_waiting_rooms, :video_id, :bigint, null: true

    # Add indexes for performance
    add_index :video_waiting_rooms, [:pool_id, :status]
    add_index :video_waiting_rooms, [:sequence_id, :status]
  end
end
