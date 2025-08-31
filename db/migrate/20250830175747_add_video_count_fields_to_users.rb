class AddVideoCountFieldsToUsers < ActiveRecord::Migration[7.2]
  def change
    add_reference :users, :sequence, foreign_key: true
    add_column :users, :videos_watched_in_current_sequence, :integer
    add_column :users, :sequence_total_videos, :integer
    add_index :users, :videos_watched_in_current_sequence
    add_index :users, :sequence_total_videos
  end
end
