class AddUserStatusToUsers < ActiveRecord::Migration[7.2]
  def change
    add_column :users, :user_status, :integer, default: 0, null: false
    add_index :users, :user_status
  end
end
