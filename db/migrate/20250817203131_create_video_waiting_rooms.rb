class CreateVideoWaitingRooms < ActiveRecord::Migration[7.2]
  def change
    create_table :video_waiting_rooms do |t|
      t.references :user, null: false, foreign_key: true
      t.string :room_id, null: true
      t.references :partner_user, null: true, foreign_key: { to_table: :users }
      t.string :status, null: false, default: 'waiting'
      t.boolean :is_initiator, default: false
      t.datetime :joined_at, null: false

      t.timestamps
    end

    # Note: Indexes will be added separately if needed
    # add_index :video_waiting_rooms, :user_id, unique: true
    # add_index :video_waiting_rooms, :status
    # add_index :video_waiting_rooms, :joined_at
    # add_index :video_waiting_rooms, :room_id
  end
end
