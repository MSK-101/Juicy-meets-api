class AddOnlineStatusToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :online_status, :string, default: 'offline'
    add_column :users, :in_chat, :boolean, default: false
    add_column :users, :last_activity_at, :datetime
    add_column :users, :total_online_time, :integer, default: 0

    add_index :users, :online_status
    add_index :users, :in_chat
    add_index :users, :last_activity_at
  end
end



