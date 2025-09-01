class AddCompletedAtToVideoWaitingRooms < ActiveRecord::Migration[7.2]
  def change
    add_column :video_waiting_rooms, :completed_at, :datetime, null: true

    # Add index for efficient querying of completed entries
    add_index :video_waiting_rooms, :completed_at
  end
end
