class CreateVideoChatSessions < ActiveRecord::Migration[7.2]
  def change
    # Check if table already exists (it might have been created by another migration)
    unless table_exists?(:video_chat_sessions)
      create_table :video_chat_sessions do |t|
        t.string :session_id, null: false
        t.references :user, null: true, foreign_key: true
        t.references :partner_user, null: true, foreign_key: { to_table: :users }
        t.references :staff_user, null: true, foreign_key: { to_table: :users }
        t.references :video, null: true, foreign_key: true
        t.references :pool, null: true, foreign_key: true
        t.references :sequence, null: true, foreign_key: true
        t.string :session_type, null: false
        t.string :status, default: 'active', null: false
        t.integer :duration_seconds
        t.datetime :started_at, null: false
        t.datetime :ended_at
        t.string :room_id
        t.text :notes

        t.timestamps
      end

      add_index :video_chat_sessions, :session_id, unique: true
      add_index :video_chat_sessions, [:user_id, :status]
      add_index :video_chat_sessions, [:pool_id, :status]
      add_index :video_chat_sessions, [:sequence_id, :status]
      add_index :video_chat_sessions, [:staff_user_id, :status]
      add_index :video_chat_sessions, [:video_id, :status]
      add_index :video_chat_sessions, :room_id
      add_index :video_chat_sessions, :started_at
    end
  end
end
