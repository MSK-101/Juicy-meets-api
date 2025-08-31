class FixVideoWaitingRoomUserIdType < ActiveRecord::Migration[7.2]
  def up
    # First, drop the table and recreate it with proper structure
    drop_table :video_waiting_rooms if table_exists?(:video_waiting_rooms)

    create_table :video_waiting_rooms do |t|
      t.references :user, null: false, foreign_key: true
      t.string :room_id, null: true
      t.references :partner_user, null: true, foreign_key: { to_table: :users }
      t.string :status, null: false, default: 'waiting'
      t.boolean :is_initiator, default: false
      t.datetime :joined_at, null: false
      t.references :pool, null: true, foreign_key: true
      t.references :sequence, null: true, foreign_key: true
      t.string :match_type, null: false, default: 'real_user'
      t.bigint :video_id, null: true

      t.timestamps
    end

    # Add indexes for performance (check if they exist first)
    add_index :video_waiting_rooms, :user_id, unique: true unless index_exists?(:video_waiting_rooms, :user_id)
    add_index :video_waiting_rooms, :status unless index_exists?(:video_waiting_rooms, :status)
    add_index :video_waiting_rooms, :room_id unless index_exists?(:video_waiting_rooms, :room_id)
    add_index :video_waiting_rooms, [:pool_id, :status] unless index_exists?(:video_waiting_rooms, [:pool_id, :status])
    add_index :video_waiting_rooms, [:sequence_id, :status] unless index_exists?(:video_waiting_rooms, [:sequence_id, :status])
  end

  def down
    # Revert back to string user_id if needed
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

    add_index :video_waiting_rooms, :user_id, unique: true
    add_index :video_waiting_rooms, :status
    add_index :video_waiting_rooms, :room_id
  end
end
