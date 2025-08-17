class ModifyVideoWaitingRoomsForStringUserIds < ActiveRecord::Migration[7.2]
  def change
    # Drop and recreate table with correct structure
    drop_table :video_waiting_rooms if table_exists?(:video_waiting_rooms)

    create_table :video_waiting_rooms do |t|
      t.string :user_id, null: false
      t.string :room_id, null: true
      t.string :partner_user_id, null: true
      t.string :status, null: false, default: 'waiting'
      t.boolean :is_initiator, default: false
      t.datetime :joined_at, null: false

      t.timestamps
    end

    # Add indexes for performance
    add_index :video_waiting_rooms, :user_id, unique: true
    add_index :video_waiting_rooms, :status
    add_index :video_waiting_rooms, :room_id
  end
end
